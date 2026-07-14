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

# ============================================================================
# Network extension — compile-time configuration
# Override with: cmake -DNETWORK_SAFE_SHUTDOWN_TIMEOUT_MS=500 ...
# ============================================================================
set(NETWORK_FIXED_HEX_SIZE 16 CACHE STRING
    "Hex string length for framing protocol (to_fixed_hex / from_fixed_hex)")
set(NETWORK_MAX_PORT 65535 CACHE STRING
    "Maximum valid TCP/UDP port number")
set(NETWORK_MAX_IO_BUFFER_SIZE 67108864 CACHE STRING
    "Maximum bytes accepted by a single read/receive/get_buffer request")
set(NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS 200 CACHE STRING
    "Drain-loop deadline in milliseconds for both UDP safe_close and TCP safe_shutdown exclusive-operation and queued-I/O drain")
set(NETWORK_TLS_SHUTDOWN_TIMEOUT_MS 5000 CACHE STRING
    "TCP safe_shutdown TLS close-notify timeout in milliseconds")
set(NETWORK_THREAD_WORKER_POLL_MS 1 CACHE STRING
    "thread_executor run_one_for polling interval in milliseconds")

find_package(OpenSSL REQUIRED)

add_library(network SHARED network.cpp)

target_compile_definitions(network PRIVATE
    NETWORK_FIXED_HEX_SIZE=${NETWORK_FIXED_HEX_SIZE}
    NETWORK_MAX_PORT=${NETWORK_MAX_PORT}
    NETWORK_MAX_IO_BUFFER_SIZE=${NETWORK_MAX_IO_BUFFER_SIZE}
    NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS=${NETWORK_SAFE_SHUTDOWN_TIMEOUT_MS}
    NETWORK_TLS_SHUTDOWN_TIMEOUT_MS=${NETWORK_TLS_SHUTDOWN_TIMEOUT_MS}
    NETWORK_THREAD_WORKER_POLL_MS=${NETWORK_THREAD_WORKER_POLL_MS}
)

target_link_libraries(network covscript OpenSSL::SSL OpenSSL::Crypto)

if (WIN32)
    target_link_libraries(network ws2_32 wsock32 bcrypt crypt32)
else ()
    target_link_libraries(network pthread)
endif ()

set_target_properties(network PROPERTIES OUTPUT_NAME network)
set_target_properties(network PROPERTIES PREFIX "")
set_target_properties(network PROPERTIES SUFFIX ".cse")