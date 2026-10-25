#!/bin/bash
set -e

MODE="${MODE:-client}"
SYNC_PROTOCOL="${SYNC_PROTOCOL:-ssh}"
REMOTE_HOST="${REMOTE_HOST:-tower}"
REMOTE_USER="${REMOTE_USER:-}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/cache/appdata/traefik}"
SOURCE_URL="${SOURCE_URL:-}"
LOCAL_PATH="${LOCAL_PATH:-/data}"
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"
CONTAINER_NAME="${CONTAINER_NAME:-traefik2}"
RESTART_DELAY="${RESTART_DELAY:-5}"
FILE_OWNER="${FILE_OWNER:-1000}"
FILE_GROUP="${FILE_GROUP:-1000}"
API_TOKEN="${API_TOKEN:-${HTTP_AUTH_TOKEN:-}}"
SSH_COMMAND="${SSH_COMMAND:-ssh -F /dev/null}"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

running=true

handle_shutdown() {
    running=false
    log "Shutdown requested"
}

sleep_interruptible() {
    local delay="$1"
    local sleep_pid

    sleep "$delay" &
    sleep_pid="$!"
    wait "$sleep_pid" || true
    if [[ "$running" != "true" ]]; then
        kill "$sleep_pid" 2>/dev/null || true
        wait "$sleep_pid" 2>/dev/null || true
    fi
}

trap handle_shutdown TERM INT

fetch_http_file() {
    local file_name="$1"
    local tmp_file="$2"
    local url="${SOURCE_URL%/}/${file_name}"
    local -a curl_args=(--fail --silent --show-error --location --connect-timeout 5 --output "$tmp_file")

    if [[ -n "$API_TOKEN" ]]; then
        curl_args=(-H "Authorization: Bearer ${API_TOKEN}" "${curl_args[@]}")
    fi

    curl "${curl_args[@]}" "$url"
}

fetch_ssh_file() {
    local file_name="$1"
    local tmp_file="$2"
    local remote_spec

    if [[ -n "$REMOTE_USER" ]]; then
        remote_spec="${REMOTE_USER}@${REMOTE_HOST}"
    else
        remote_spec="${REMOTE_HOST}"
    fi

    rsync -az --checksum -e "$SSH_COMMAND" "${remote_spec}:${REMOTE_PATH}/${file_name}" "$tmp_file"
}

fetch_file() {
    local file_name="$1"
    local tmp_file="$2"

    case "$SYNC_PROTOCOL" in
        ssh)
            fetch_ssh_file "$file_name" "$tmp_file"
            ;;
        http)
            fetch_http_file "$file_name" "$tmp_file"
            ;;
        *)
            echo "Unsupported SYNC_PROTOCOL: $SYNC_PROTOCOL" >&2
            return 1
            ;;
    esac
}

apply_file() {
    local file_name="$1"
    local tmp_file="$2"
    local target_file="${LOCAL_PATH}/${file_name}"

    if [[ -f "$target_file" ]] && cmp -s "$tmp_file" "$target_file"; then
        rm -f "$tmp_file"
        return 1
    fi

    chown "${FILE_OWNER}:${FILE_GROUP}" "$tmp_file" 2>/dev/null || true
    mv -f "$tmp_file" "$target_file"
    log "Updated ${file_name}"
    return 0
}

restart_target() {
    log "acme.json changed, restarting ${CONTAINER_NAME} in ${RESTART_DELAY}s"
    sleep_interruptible "$RESTART_DELAY"
    [[ "$running" == "true" ]] || return 0
    if docker restart "$CONTAINER_NAME"; then
        log "Container ${CONTAINER_NAME} restarted successfully"
    else
        log "ERROR: Failed to restart ${CONTAINER_NAME}"
    fi
}

if [[ "$MODE" != "client" ]]; then
    echo "sync.sh only supports MODE=client" >&2
    exit 1
fi

if [[ "$SYNC_PROTOCOL" == "http" ]] && [[ -z "$SOURCE_URL" ]]; then
    echo "SOURCE_URL is required when SYNC_PROTOCOL=http" >&2
    exit 1
fi

mkdir -p "$LOCAL_PATH"

log "Starting traefik-sync"
case "$SYNC_PROTOCOL" in
    ssh)
        if [[ -n "$REMOTE_USER" ]]; then
            log "Remote: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
        else
            log "Remote: ${REMOTE_HOST}:${REMOTE_PATH}"
        fi
        ;;
    http)
        log "Source URL: ${SOURCE_URL%/}"
        ;;
esac
log "Local: ${LOCAL_PATH}"
log "Interval: ${SYNC_INTERVAL}s"
log "Container: ${CONTAINER_NAME}"
log "File ownership: ${FILE_OWNER}:${FILE_GROUP}"

initial_sync_done=false

while [[ "$running" == "true" ]]; do
    acme_changed=false

    for file_name in acme.json fileConfig.yml; do
        # Same directory as the target, so apply_file's mv is an atomic rename. A temp
        # file under /tmp crosses filesystems: mv then unlinks the target before copying,
        # and Traefik's file watcher sees fileConfig.yml missing and drops every @file
        # middleware until the next event.
        tmp_file=$(mktemp "${LOCAL_PATH}/.${file_name}.XXXXXX")
        if fetch_file "$file_name" "$tmp_file"; then
            if apply_file "$file_name" "$tmp_file"; then
                if [[ "$file_name" == "acme.json" ]]; then
                    acme_changed=true
                fi
            fi
        else
            rm -f "$tmp_file"
            log "Warning: failed to sync ${file_name}"
        fi
    done

    if [[ "$acme_changed" == "true" && "$initial_sync_done" == "true" ]]; then
        restart_target
    fi

    initial_sync_done=true
    sleep_interruptible "$SYNC_INTERVAL"
done

log "Stopped traefik-sync"
