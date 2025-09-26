#!/bin/bash

# Binary search for maximum stable concurrent connections with QPS output
# Usage: ./max_concurrency_binary.sh http://127.0.0.1:8080 4 1000 100000
# Arguments:
# $1 = Test URL
# $2 = wrk thread count
# $3 = Minimum connections to start
# $4 = Maximum connections to test

URL=${1:-http://127.0.0.1:8080}
THREADS=${2:-4}
MIN_CONN=${3:-1000}
MAX_CONN=${4:-100000}

LAST_OK_CONN=$MIN_CONN
LOW=$MIN_CONN
HIGH=$MAX_CONN
MAX_ITER=20
ITER=0

while (( LOW <= HIGH && ITER < MAX_ITER ))
do
    ((ITER++))
    MID=$(( (LOW + HIGH) / 2 ))
    echo "Testing concurrency: $MID"

    # Run wrk for 10 seconds to speed up binary search
    OUTPUT=$(wrk -t$THREADS -c$MID -d10s $URL 2>&1)

    # Extract the number of connect errors
    CONN_ERR=$(echo "$OUTPUT" | grep -oP 'Socket errors: connect \K[0-9]+')
    CONN_ERR=${CONN_ERR:-0}

    # Extract Requests/sec
    REQ_PER_SEC=$(echo "$OUTPUT" | grep -oP 'Requests/sec:\s*\K[0-9.]+')

    echo "Connect errors: $CONN_ERR, QPS: $REQ_PER_SEC"

    # Consider connection stable if errors <= 1% of MID
    THRESHOLD=$(( MID / 100 ))
    if (( CONN_ERR <= THRESHOLD )); then
        # Stable, try higher concurrency
        LAST_OK_CONN=$MID
        LOW=$(( MID + 1 ))
    else
        # Unstable, reduce concurrency
        HIGH=$(( MID - 1 ))
    fi
done

echo "Maximum stable concurrent connections: $LAST_OK_CONN"
