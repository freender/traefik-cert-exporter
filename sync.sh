#!/bin/bash
set -e

REMOTE_HOST="${REMOTE_HOST:-tower}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/cache/appdata/traefik}"
LOCAL_PATH="${LOCAL_PATH:-/data}"
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"
CONTAINER_NAME="${CONTAINER_NAME:-traefik2}"
RESTART_DELAY="${RESTART_DELAY:-5}"
FILE_OWNER="${FILE_OWNER:-1000}"
FILE_GROUP="${FILE_GROUP:-1000}"

LAST_MOD=0

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting traefik-sync"
echo "  Remote: ${REMOTE_HOST}:${REMOTE_PATH}"
echo "  Local: ${LOCAL_PATH}"
echo "  Interval: ${SYNC_INTERVAL}s"
echo "  Container: ${CONTAINER_NAME}"
echo "  File ownership: ${FILE_OWNER}:${FILE_GROUP}"

while true; do
    # Sync files from remote
    if rsync -az --checksum -e "ssh -F /dev/null" "${REMOTE_HOST}:${REMOTE_PATH}/acme.json" "${LOCAL_PATH}/"; then
        chown "${FILE_OWNER}:${FILE_GROUP}" "${LOCAL_PATH}/acme.json" 2>/dev/null || true
    else
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Warning: rsync acme.json failed"
    fi
    
    if rsync -az --checksum -e "ssh -F /dev/null" "${REMOTE_HOST}:${REMOTE_PATH}/fileConfig.yml" "${LOCAL_PATH}/"; then
        chown "${FILE_OWNER}:${FILE_GROUP}" "${LOCAL_PATH}/fileConfig.yml" 2>/dev/null || true
    else
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Warning: rsync fileConfig.yml failed"
    fi

    # Check if acme.json changed
    CURRENT_MOD=$(stat -c %Y "${LOCAL_PATH}/acme.json" 2>/dev/null || echo 0)
    if [[ "$CURRENT_MOD" != "$LAST_MOD" && "$LAST_MOD" != "0" ]]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] acme.json changed (was: $LAST_MOD, now: $CURRENT_MOD), restarting ${CONTAINER_NAME} in ${RESTART_DELAY}s"
        sleep "$RESTART_DELAY"
        if docker restart "$CONTAINER_NAME"; then
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Container ${CONTAINER_NAME} restarted successfully"
        else
            echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: Failed to restart ${CONTAINER_NAME}"
        fi
    fi
    LAST_MOD="$CURRENT_MOD"

    sleep "$SYNC_INTERVAL"
done
