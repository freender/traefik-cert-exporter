# traefik-sync

Lightweight Docker image that syncs Traefik ACME certificates from a source instance to failover instances.

## Overview

The same image runs in two modes:

1. `MODE=server` on the source host, serving `acme.json` and `fileConfig.yml`
2. `MODE=client` on failover hosts, pulling those files on an interval
3. Fixes file ownership to match the local Traefik container user
4. Automatically restarts the local Traefik container when certificates update

## Features

- **Single image**: Same container image for source and failover roles
- **HTTP mode**: Overlay-network sync without mounting SSH keys into containers
- **SSH mode**: Existing rsync-over-SSH flow still supported for compatibility
- **Automatic restart**: Triggers Traefik container restart on cert changes
- **File ownership**: Ensures synced files match Traefik container user
- **Configurable**: Environment variables for all settings
- **Lightweight**: Alpine-based image with Bash, curl, Python, rsync, and docker-cli
- **Multi-arch**: Supports linux/amd64 and linux/arm64

## Quick Start

See [docker-compose.example.yml](docker-compose.example.yml) for complete source + client examples.

Source host (`tower`) with overlay-only HTTP serving:

```yaml
services:
  traefik-sync-source:
    image: ghcr.io/freender/traefik-sync:main
    container_name: traefik-sync-source
    restart: always
    environment:
      MODE: server
      SERVE_PATH: /source
      LISTEN_PORT: 8080
      API_TOKEN: change-me
    volumes:
      - /mnt/cache/appdata/traefik:/source:ro
    networks:
      - net.internal
```

Failover host (`helm` or `orbit`) pulling from the source service:

```yaml
services:
  traefik-sync:
    image: ghcr.io/freender/traefik-sync:main
    container_name: traefik-sync
    restart: always
    environment:
      MODE: client
      SYNC_PROTOCOL: http
      SOURCE_URL: http://traefik-sync-source:8080
      API_TOKEN: change-me
      LOCAL_PATH: /data
      SYNC_INTERVAL: 60
      CONTAINER_NAME: traefik2
      RESTART_DELAY: 5
      FILE_OWNER: 1000
      FILE_GROUP: 1000
    volumes:
      - /path/to/failover/traefik:/data
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - net.internal
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `MODE` | `client` | `client` to sync files, `server` to serve them |
| `SYNC_PROTOCOL` | `ssh` | Client protocol: `ssh` or `http` |
| `SOURCE_URL` | `` | Base URL for HTTP mode, for example `http://traefik-sync-source:8080` |
| `API_TOKEN` | `` | Optional bearer token for HTTP mode |
| `REMOTE_HOST` | `tower` | Source hostname for SSH mode |
| `REMOTE_USER` | `` | SSH user for SSH mode |
| `REMOTE_PATH` | `/mnt/cache/appdata/traefik` | Source directory for SSH mode |
| `SSH_COMMAND` | `ssh -F /dev/null` | SSH command passed to rsync in SSH mode |
| `SERVE_PATH` | `/source` | Source directory served in server mode |
| `LISTEN_HOST` | `0.0.0.0` | Bind host for server mode |
| `LISTEN_PORT` | `8080` | Bind port for server mode |
| `LOCAL_PATH` | `/data` | Client destination directory |
| `SYNC_INTERVAL` | `60` | Client sync interval in seconds |
| `CONTAINER_NAME` | `traefik2` | Client Traefik container to restart |
| `RESTART_DELAY` | `5` | Delay before restarting Traefik |
| `FILE_OWNER` | `1000` | UID for synced files |
| `FILE_GROUP` | `1000` | GID for synced files |

## Requirements

1. **Shared network reachability** between source and failover containers
2. **Docker socket access** on failover for container restart capability
3. **Correct FILE_OWNER/FILE_GROUP** - must match your Traefik container user
4. For HTTP mode, set the same `API_TOKEN` on source and clients

For SSH mode, keep the existing SSH key access to the source host.

Check Traefik container user:

```bash
docker exec <traefik-container> id
```

## Architecture

```
SOURCE HOST (tower)                      FAILOVER HOST (helm/orbit)
/path/to/traefik/                        /path/to/traefik/
├── acme.json      ◄─── HTTP pull ─────── traefik-sync (MODE=client)
├── fileConfig.yml ◄─── overlay net ───   └─ Restarts Traefik on change
└── traefik-sync-source                  ├── acme.json (synced)
    (MODE=server)                        ├── fileConfig.yml (synced)
                                         └── traefik.yml
```

## Logs

Monitor sync activity:

```bash
docker logs -f traefik-sync
docker logs -f traefik-sync-source
```

Example client output:

```text
[2026-03-26T22:10:22Z] Starting traefik-sync
[2026-03-26T22:10:22Z] Source URL: http://traefik-sync-source:8080
[2026-03-26T22:10:22Z] Local: /data
[2026-03-26T22:10:22Z] Interval: 60s
[2026-03-26T22:10:22Z] Container: traefik2
[2026-03-26T22:10:22Z] File ownership: 1000:1000
[2026-03-26T22:11:26Z] Updated acme.json
[2026-03-26T22:11:26Z] Updated fileConfig.yml
[2026-03-26T22:11:26Z] acme.json changed, restarting traefik2 in 5s
[2026-03-26T22:11:31Z] Container traefik2 restarted successfully
```

## Troubleshooting

**HTTP mode fails:**

```bash
# Test source endpoint from client container
docker exec traefik-sync curl -H "Authorization: Bearer <token>" http://traefik-sync-source:8080/healthz

# Test file access
docker exec traefik-sync curl -I -H "Authorization: Bearer <token>" http://traefik-sync-source:8080/acme.json
```

**SSH mode fails:**

```bash
# Test SSH from container
docker exec traefik-sync ssh <master-host> "echo test"

# Check SSH config
docker exec traefik-sync ls -la /root/.ssh/
```

**File ownership incorrect:**

```bash
# Check current ownership
ls -la /path/to/traefik/acme.json

# Verify Traefik container user
docker exec <traefik-container> id

# Update FILE_OWNER and FILE_GROUP to match
```

**Container not restarting Traefik:**

```bash
# Check Docker socket access
docker exec traefik-sync docker ps

# Verify container name
docker ps | grep traefik
```

## Development

Build locally:

```bash
docker build -t traefik-sync .
```

GitHub Actions automatically builds and publishes to `ghcr.io/freender/traefik-sync:main` on push to main.

## License

MIT
