cmake_minimum_required(VERSION 3.4)

project(covscript-network)
include_directories(include)

if (DEFINED ENV{CS_DEV_PATH})
    include_directories($ENV{CS_DEV_PATH}/include)
    link_directories($ENV{CS_DEV_PATH}/lib)
endif ()

if (DEFINED ENV{CS_DEV_OUTPUT})
    set(LIBRARY_OUTPUT_PATH $ENV{CS_DEV_OUTPUT})
    set(EXECUTABLE_OUTPUT_PATH $ENV{CS_DEV_OUTPUT})
endif ()

# Compiler Options
set(CMAKE_CXX_STANDARD 14)

if (MSVC)
    set(CMAKE_CXX_FLAGS "/O2 /EHsc /utf-8 /w")
    set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)
elseif (CMAKE_COMPILER_IS_GNUCXX)
    if (WIN32)
        set(CMAKE_C_FLAGS "--static -fPIC -s -O3")
        set(CMAKE_CXX_FLAGS "--static -fPIC -s -O3")
    else ()
        set(CMAKE_C_FLAGS "-fPIC -s -O3")
        set(CMAKE_CXX_FLAGS "-fPIC -s -O3")
    endif ()
else ()
    set(CMAKE_C_FLAGS "-fPIC -O3")
    set(CMAKE_CXX_FLAGS "-fPIC -O3")
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