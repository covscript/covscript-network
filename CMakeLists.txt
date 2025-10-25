cmake_minimum_required(VERSION 3.10)

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
    # MSVC Windows
    set(CMAKE_CXX_FLAGS "/O2 /EHsc /utf-8 /DNDEBUG /Zc:__cplusplus /MP /w")
    set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)
    set(CMAKE_RC_FLAGS "/nologo /c65001")
elseif (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    # Common flags for GCC/Clang
    set(CMAKE_CXX_FLAGS "-O2 -DNDEBUG -fPIC")
    if (WIN32)
        # MinGW or Clang on Windows
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} --static")
    elseif (UNIX AND NOT APPLE)
        # Linux
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-plt")
    elseif (APPLE)
        # macOS
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    endif ()
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