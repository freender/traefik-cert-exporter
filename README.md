# traefik-sync

Lightweight Docker container that syncs Traefik ACME certificates from a master instance to failover instances.

## Overview

This container runs on failover Traefik instances and:
1. Pulls `acme.json` and `fileConfig.yml` from the master instance via rsync over SSH
2. Detects changes to `acme.json` using file modification timestamps
3. Fixes file ownership to match Traefik container user
4. Automatically restarts the Traefik container when certificates update

## Features

- **Rsync + stat**: Simple periodic sync with change detection
- **SSH-based**: Secure file transfer using existing SSH keys
- **Automatic restart**: Triggers Traefik container restart on cert changes
- **File ownership**: Ensures synced files match Traefik container user
- **Configurable**: Environment variables for all settings
- **Lightweight**: Alpine-based, ~45MB image
- **Multi-arch**: Supports linux/amd64 and linux/arm64

## Quick Start

See [docker-compose.example.yml](docker-compose.example.yml) for a complete example configuration.

Add to your Traefik compose.yml on the **failover host**:

```yaml
services:
  traefik-sync:
    image: ghcr.io/freender/traefik-sync:main
    container_name: traefik-sync
    restart: always
    mem_limit: 128m
    environment:
      REMOTE_HOST: master.example.com
      REMOTE_PATH: /path/to/master/traefik
      LOCAL_PATH: /data
      SYNC_INTERVAL: 60
      CONTAINER_NAME: traefik
      RESTART_DELAY: 5
      FILE_OWNER: 1000
      FILE_GROUP: 1000
    volumes:
      - ~/.ssh:/root/.ssh:ro
      - /path/to/failover/traefik:/data
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - traefik_network
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `REMOTE_HOST` | `tower` | Master Traefik hostname (use FQDN) |
| `REMOTE_PATH` | `/mnt/cache/appdata/traefik` | Master Traefik config directory |
| `LOCAL_PATH` | `/data` | Local mount point for Traefik config |
| `SYNC_INTERVAL` | `60` | Sync interval in seconds |
| `CONTAINER_NAME` | `traefik2` | Name of Traefik container to restart |
| `RESTART_DELAY` | `5` | Delay before restart in seconds |
| `FILE_OWNER` | `1000` | UID for synced files |
| `FILE_GROUP` | `1000` | GID for synced files |

## Requirements

1. **SSH key access** from failover to master (passwordless authentication)
2. **Master hostname** must be resolvable (use FQDN or add to /etc/hosts)
3. **Docker socket access** for container restart capability
4. **Correct FILE_OWNER/FILE_GROUP** - must match your Traefik container user

Check Traefik container user:
```bash
docker exec <traefik-container> id
```

## Architecture

```
MASTER (generates certs)              FAILOVER (syncs certs)
/path/to/traefik/                     /path/to/traefik/
├── acme.json      ◄─── rsync (60s) ─── traefik-sync container
├── fileConfig.yml ◄─── SSH pull   ───   └─ Restarts Traefik on change
└── traefik.yml                      ├── acme.json (synced)
                                     ├── fileConfig.yml (synced)
                                     └── traefik.yml
```

## Logs

Monitor sync activity:
```bash
docker logs -f traefik-sync
```

Example output:
```
[2026-01-25T18:10:22Z] Starting traefik-sync
  Remote: master.example.com:/path/to/traefik
  Local: /data
  Interval: 60s
  Container: traefik
  File ownership: 1000:1000
[2026-01-25T18:11:26Z] acme.json changed (was: 1769363615, now: 1769364076), restarting traefik in 5s
[2026-01-25T18:11:31Z] Container traefik restarted successfully
```

## Troubleshooting

**SSH connection fails:**
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
