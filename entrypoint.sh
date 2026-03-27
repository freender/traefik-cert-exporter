#!/bin/bash
set -e

MODE="${MODE:-client}"

case "$MODE" in
    client)
        exec /sync.sh
        ;;
    server)
        exec python3 /server.py
        ;;
    *)
        echo "Unsupported MODE: $MODE" >&2
        exit 1
        ;;
esac
