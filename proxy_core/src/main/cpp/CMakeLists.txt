cmake_minimum_required(VERSION 3.5.0)
project(proxy_core)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(proxy_core SHARED
    core_bridge.cpp
    core_napi.cpp
    napi_init.cpp
)

# Native dependencies are packaged beside libproxy_core.so in the HAP. Do not
# leak the host prebuilt directory into DT_RUNPATH, because it is meaningless
# (and rejected by some loaders) on a HarmonyOS device.
set_target_properties(proxy_core PROPERTIES
    SKIP_BUILD_RPATH TRUE
    BUILD_WITH_INSTALL_RPATH FALSE
    INSTALL_RPATH ""
)

target_include_directories(proxy_core PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

if(OHOS_ARCH STREQUAL "arm64-v8a")
    set(NLASH_CORE_PREBUILT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/arm64-v8a)
    add_library(nlash_core SHARED IMPORTED)
    set_target_properties(nlash_core PROPERTIES
        IMPORTED_LOCATION ${NLASH_CORE_PREBUILT_DIR}/libnlash_core.so
    )
    target_include_directories(proxy_core PRIVATE ${NLASH_CORE_PREBUILT_DIR})
    target_compile_definitions(proxy_core PRIVATE NLASH_HAS_GO_CORE=1)
    target_link_libraries(proxy_core PUBLIC nlash_core)
endif()

target_link_libraries(proxy_core PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
)
