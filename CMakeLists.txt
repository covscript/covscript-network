cmake_minimum_required(VERSION 3.16)

project(covscript-network)
include_directories(include)

if (DEFINED ENV{CS_DEV_PATH})
    message("-- CovScript SDK detected at $ENV{CS_DEV_PATH}")
    include("$ENV{CS_DEV_PATH}/csbuild.cmake")
    include_directories($ENV{CS_DEV_PATH}/include)
    link_directories($ENV{CS_DEV_PATH}/lib)
else ()
    message(FATAL_ERROR "-- CovScript SDK not detected. Please set environment variable CS_DEV_PATH")
endif ()

add_library(network SHARED network.cpp)

target_link_libraries(network covscript)

if (WIN32)
    target_link_libraries(network ws2_32 wsock32)
else ()
    target_link_libraries(network pthread)
endif ()

set_target_properties(network PROPERTIES OUTPUT_NAME network)
set_target_properties(network PROPERTIES PREFIX "")
set_target_properties(network PROPERTIES SUFFIX ".cse")