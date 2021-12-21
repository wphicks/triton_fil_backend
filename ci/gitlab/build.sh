#!/bin/bash

set -e

# ENVIRONMENT VARIABLE OPTIONS
# PREBUILT_SERVER_TAG: The tag of the prebuilt Triton server image to test
# PREBUILT_TEST_TAG: The tag of the prebuilt test image to run tests in
# MODEL_BUILDER_IMAGE: A Docker image to be used for training test models
# LOG_DIR: Host directory for storing logs
# NV_DOCKER_ARGS: A bash expression that (when evaluated) returns Docker
#   arguments for controlling GPU access
# BUILDPY: 1 to use Triton's build.py script for server build
# CPU_ONLY: 1 to build without GPU support
# NO_CACHE: 0 to enable Docker cache during build
# REPO_DIR: The directory of the FIL backend repository. If not set, an attempt
#   will be made to automatically detect it.

if [ -z $REPO_DIR ]
then
  SCRIPT_DIR=$(cd $(dirname $0); pwd)
  REPO_DIR=$(cd ${REPO_DIR}/../../; pwd)
fi
QA_DIR="${REPO_DIR}/qa"
MODEL_DIR="${QA_DIR}/L0_e2e/model_repository"
CPU_MODEL_DIR="${QA_DIR}/L0_e2e/cpu_model_repository"
BUILDPY=${BUILDPY:-0}
CPU_ONLY=${CPU_ONLY:-0}
NO_CACHE=${CPU_ONLY:-1}

# Check if test or base images need to be built and do so if necessary
if [ -z $PREBUILT_SERVER_TAG ]
then
  export SERVER_TAG=triton_fil
else
  export PREBUILT_IMAGE="$PREBUILT_SERVER_TAG"
  export SERVER_TAG="$PREBUILT_SERVER_TAG"
fi
if [ -z $PREBUILT_TEST_TAG ]
then
  export TEST_TAG=triton_fil_test
  echo "Building Docker images..."
  if [ $BUILDPY -eq 1 ]
  then
    BUILDARGS='--buildpy'
  else
    BUILDARGS=''
  fi
  if [ $CPU_ONLY -eq 1 ]
  then
    BUILDARGS="$BUILDARGS --cpu-only"
  fi
  if [ $NO_CACHE -eq 1 ]
  then
    BUILDARGS="$BUILDARGS --no-cache"
  fi
  $REPO_DIR/build.sh $BUILDARGS
else
  export TEST_TAG="$PREBUILT_TEST_TAG"
fi

MODEL_BUILDER_IMAGE=${MODEL_BUILDER_IMAGE:-${TEST_TAG}}

# Set up directory for logging
if [ -z $LOG_DIR ]
then
  LOG_DIR="${QA_DIR}/logs"
fi
if [ ! -d "${LOG_DIR}" ]
then
  mkdir -p "${LOG_DIR}"
fi
LOG_DIR="$(readlink -f $LOG_DIR)"

DOCKER_ARGS="-v ${LOG_DIR}:/qa/logs"

if [ -z "$NV_DOCKER_ARGS" ]
then
  if [ -z $CUDA_VISIBLE_DEVICES ]
  then
    GPU_DOCKER_ARGS='--gpus all'
  else
    GPU_DOCKER_ARGS='--gpus $CUDA_VISIBLE_DEVICES'
  fi
else
  GPU_DOCKER_ARGS="$(eval ${NV_DOCKER_ARGS})"
fi

echo "Running linters..."
docker run \
  $DOCKER_ARGS \
  -v "${REPO_DIR}:/rapids_triton_src" \
  --rm $TEST_TAG \
  bash -c 'cd /rapids_triton_src && conda run -n triton_test python qa/run-clang-format.py && conda run -n triton_test flake8'

echo "Generating example models..."
docker run \
  -e RETRAIN=1 \
  -e OWNER_ID=$(id -u) \
  -e OWNER_GID=$(id -g) \
  $GPU_DOCKER_ARGS \
  $DOCKER_ARGS \
  -v "${MODEL_DIR}:/qa/L0_e2e/model_repository" \
  -v "${CPU_MODEL_DIR}:/qa/L0_e2e/cpu_model_repository" \
  $MODEL_BUILDER_IMAGE \
  bash -c 'conda run -n triton_test /qa/generate_example_models.sh'

if [ $CPU_ONLY -eq 1 ]
then
  DOCKER_ARGS="${DOCKER_ARGS} -e TRITON_ENABLE_GPU=OFF"
else
  DOCKER_ARGS="${DOCKER_ARGS} ${GPU_DOCKER_ARGS}"
fi

echo "Running tests..."
docker run \
  $DOCKER_ARGS \
  -v "${MODEL_DIR}:/qa/L0_e2e/model_repository" \
  -v "${CPU_MODEL_DIR}:/qa/L0_e2e/cpu_model_repository" \
  --rm $TEST_TAG
