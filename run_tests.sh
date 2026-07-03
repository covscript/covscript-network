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
         tests/test_header_parser.csc \
         tests/test_utils.csc \
         tests/test_tcp_sync.csc \
         tests/test_udp.csc \
         tests/test_http_roundtrip.csc \
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
