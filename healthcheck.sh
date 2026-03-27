#!/bin/bash
set -e

MODE="${MODE:-client}"

case "$MODE" in
    client)
        pgrep -f /sync.sh >/dev/null
        ;;
    server)
        curl -fsS "http://127.0.0.1:${LISTEN_PORT:-8080}/healthz" >/dev/null
        ;;
    *)
        exit 1
        ;;
esac
