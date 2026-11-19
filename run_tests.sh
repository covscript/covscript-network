#!/usr/bin/env bash
set -e

CS="${CS:-cs}"
IMPORT_FLAGS="-i build/imports"

echo "============================================"
echo "  CovScript Network Extension - Test Runner"
echo "============================================"

echo ""
echo "=== Unit Tests ==="

for t in tests/test_url_parse.csc \
         tests/test_argparse.csc \
         tests/test_header_parser.csc \
         tests/test_utils.csc \
         tests/test_tcp_sync.csc \
         tests/test_udp.csc \
         tests/test_ipv6.csc \
         tests/test_http_roundtrip.csc \
         tests/test_http_client.csc \
         tests/test_http_server.csc \
         tests/test_proxy.csc \
         tests/test_openai_client.csc \
         tests/test_fiber_socket.csc \
         tests/test_async_tcp.csc; do
    echo ""
    echo "--- $t ---"
    "$CS" $IMPORT_FLAGS "$t"
done

echo ""
echo "=== Integration Tests ==="

echo ""
echo "--- tests/test_tls_trust.csc ---"
"$CS" $IMPORT_FLAGS tests/test_tls_trust.csc

echo ""
echo "--- tests/test_tls_errors.csc ---"
"$CS" $IMPORT_FLAGS tests/test_tls_errors.csc

echo ""
echo "--- tests/test_master_slave.csc ---"
"$CS" $IMPORT_FLAGS tests/test_master_slave.csc

echo ""
echo "--- tests/test_http_compliance.csc ---"
"$CS" $IMPORT_FLAGS tests/test_http_compliance.csc

echo ""
echo "--- tests/test_error_paths.csc ---"
"$CS" $IMPORT_FLAGS tests/test_error_paths.csc

echo ""
echo "--- tests/test_stress_keepalive.csc ---"
"$CS" $IMPORT_FLAGS tests/test_stress_keepalive.csc

echo ""
echo "--- tests/test_stress_concurrent.csc ---"
"$CS" $IMPORT_FLAGS tests/test_stress_concurrent.csc

echo ""
echo "--- tests/test_stress_master_slave.csc ---"
"$CS" $IMPORT_FLAGS tests/test_stress_master_slave.csc

# TLS custom trust mode against a local self-signed server (mirrors CI step
# 16d). Requires openssl; skipped when unavailable.
if command -v openssl >/dev/null 2>&1; then
    echo ""
    echo "--- tests/test_tls_trust.csc (custom trust, self-signed) ---"
    # MSYS2/MinGW converts /CN= to a Windows path; //CN= prevents this.
    case "$(uname 2>/dev/null)" in
        MINGW*|MSYS*) SUBJ='//CN=localhost' ;;
        *)            SUBJ='/CN=localhost' ;;
    esac
    openssl req -x509 -newkey rsa:2048 \
        -keyout /tmp/test-key.pem -out /tmp/test-cert.pem \
        -days 1 -nodes -subj "$SUBJ" 2>/dev/null
    openssl s_server -cert /tmp/test-cert.pem -key /tmp/test-key.pem \
        -port 19443 -www -quiet 2>/dev/null &
    SERVER_PID=$!
    trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
    sleep 1
    "$CS" $IMPORT_FLAGS tests/test_tls_trust.csc localhost 19443 /tmp/test-cert.pem
else
    echo ""
    echo "SKIP: TLS custom trust test (openssl not found)"
fi

if [ -n "$DEEPSEEK_API_KEY" ]; then
    echo ""
    echo "--- tests/test_deepseek.csc ---"
    "$CS" $IMPORT_FLAGS tests/test_deepseek.csc
else
    echo ""
    echo "SKIP: tests/test_deepseek.csc (DEEPSEEK_API_KEY not set)"
fi

echo ""
echo "============================================"
echo "  All tests completed"
echo "============================================"
