@echo off
setlocal enabledelayedexpansion

set CS=%CS%
if "%CS%"=="" set CS=cs

set IMPORT_FLAGS=-i build/imports

echo ============================================
echo   CovScript Network Extension - Test Runner
echo ============================================

echo.
echo === Unit Tests ===

for %%t in (
    tests\test_url_parse.csc
    tests\test_header_parser.csc
    tests\test_utils.csc
    tests\test_tcp_sync.csc
    tests\test_udp.csc
    tests\test_http_roundtrip.csc
    tests\test_openai_client.csc
    tests\test_fiber_socket.csc
    tests\test_async_tcp.csc
) do (
    echo.
    echo --- %%t ---
    %CS% %IMPORT_FLAGS% %%t
    if errorlevel 1 exit /b 1
)

echo.
echo === Integration Tests ===

echo.
echo --- tests\test_tls_trust.csc ---
%CS% %IMPORT_FLAGS% tests\test_tls_trust.csc
if errorlevel 1 exit /b 1

echo.
echo --- tests\test_tls_errors.csc ---
%CS% %IMPORT_FLAGS% tests\test_tls_errors.csc
if errorlevel 1 exit /b 1

if not "%DEEPSEEK_API_KEY%"=="" (
    echo.
    echo --- tests\test_deepseek.csc ---
    %CS% %IMPORT_FLAGS% tests\test_deepseek.csc
    if errorlevel 1 exit /b 1
) else (
    echo.
    echo SKIP: tests\test_deepseek.csc (DEEPSEEK_API_KEY not set)
)

echo.
echo ============================================
echo   All tests completed
echo ============================================
