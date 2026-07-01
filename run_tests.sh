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
         tests/test_openai_client.csc \
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
echo "--- tests/test_deepseek.csc ---"
"$CS" $IMPORT_FLAGS tests/test_deepseek.csc

echo ""
echo "============================================"
echo "  All tests completed"
echo "============================================"
