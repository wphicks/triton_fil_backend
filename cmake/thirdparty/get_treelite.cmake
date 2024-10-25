#=============================================================================
# Copyright (c) 2021-2022, NVIDIA CORPORATION.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#=============================================================================

function(find_and_configure_treelite)

    set(oneValueArgs VERSION PINNED_TAG BUILD_STATIC_LIBS)
    cmake_parse_arguments(PKG "${options}" "${oneValueArgs}"
                          "${multiValueArgs}" ${ARGN} )

    message(VERBOSE "CUML: In treelite func, static: ${PKG_BUILD_STATIC_LIBS}")
    if(NOT PKG_BUILD_STATIC_LIBS)
        list(APPEND TREELITE_LIBS treelite::treelite)
    else()
        list(APPEND TREELITE_LIBS treelite::treelite_static)
    endif()

    rapids_cpm_find(Treelite ${PKG_VERSION}
        GLOBAL_TARGETS       ${TREELITE_LIBS}
        INSTALL_EXPORT_SET   cuml-exports
        CPM_ARGS
            GIT_REPOSITORY   https://github.com/hcho3/treelite.git
            GIT_TAG          ${PKG_PINNED_TAG}
            OPTIONS
              "USE_OPENMP ON"
              "Treelite_BUILD_STATIC_LIBS ${PKG_BUILD_STATIC_LIBS}"
    )


    list(APPEND TREELITE_LIBS_NO_PREFIX treelite)
    if(Treelite_ADDED AND PKG_BUILD_STATIC_LIBS)
        list(APPEND TREELITE_LIBS_NO_PREFIX treelite_static)
    endif()

    set(Treelite_ADDED ${Treelite_ADDED} PARENT_SCOPE)
    set(TREELITE_LIBS ${TREELITE_LIBS} PARENT_SCOPE)

    if(Treelite_ADDED)
        if (NOT PKG_BUILD_STATIC_LIBS)
            target_include_directories(treelite
                PUBLIC $<BUILD_INTERFACE:${Treelite_SOURCE_DIR}/include>
                       $<BUILD_INTERFACE:${Treelite_BINARY_DIR}/include>)
            if(NOT TARGET treelite::treelite)
                add_library(treelite::treelite ALIAS treelite)
            endif()
        else()
            target_include_directories(treelite_static
                PUBLIC $<BUILD_INTERFACE:${Treelite_SOURCE_DIR}/include>
                       $<BUILD_INTERFACE:${Treelite_BINARY_DIR}/include>)
            if(NOT TARGET treelite::treelite_static)
                add_library(treelite::treelite_static ALIAS treelite_static)
            endif()
        endif()

        rapids_export(BUILD Treelite
            EXPORT_SET TreeliteTargets
            GLOBAL_TARGETS ${TREELITE_LIBS_NO_PREFIX}
            NAMESPACE treelite::)
    endif()

    # We generate the treelite-config files when we built treelite locally, so always do `find_dependency`
    rapids_export_package(BUILD Treelite cuml-exports)

    # Tell cmake where it can find the generated treelite-config.cmake we wrote.
    include("${rapids-cmake-dir}/export/find_package_root.cmake")
    rapids_export_find_package_root(BUILD Treelite [=[${CMAKE_CURRENT_LIST_DIR}]=] EXPORT_SET cuml-exports)
endfunction()

find_and_configure_treelite(VERSION     4.3.0
                        PINNED_TAG  27a8c7ad5c5697f01b176608e797e518bf6efafb
                        BUILD_STATIC_LIBS ${TRITON_FIL_USE_TREELITE_STATIC})
