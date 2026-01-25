# traefik-sync

Lightweight Docker container that syncs Traefik ACME certificates from a master instance to failover instances.

## Overview

This container runs on failover Traefik instances and:
1. Pulls `acme.json` and `fileConfig.yml` from the master instance via rsync over SSH
2. Detects changes to `acme.json` using file modification timestamps
3. Automatically restarts the Traefik container when certificates update

## Features

- **Rsync + stat**: Simple periodic sync with change detection
- **SSH-based**: Secure file transfer using existing SSH keys
- **Automatic restart**: Triggers Traefik container restart on cert changes
- **Configurable**: Environment variables for all settings
- **Lightweight**: Alpine-based, ~30MB image

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `REMOTE_HOST` | `tower` | Master Traefik hostname |
| `REMOTE_PATH` | `/mnt/cache/appdata/traefik` | Master Traefik config directory |
| `LOCAL_PATH` | `/data` | Local mount point for Traefik config |
| `SYNC_INTERVAL` | `60` | Sync interval in seconds |
| `CONTAINER_NAME` | `traefik2` | Name of Traefik container to restart |
| `RESTART_DELAY` | `5` | Delay before restart in seconds |

## Usage

### docker-compose.yml example

See your actual compose.yml for integration with existing Traefik services.

### Requirements

1. SSH key access from failover to master (passwordless)
2. Master hostname in SSH known_hosts
3. Docker socket access for container restart

## Architecture

Master instance generates certificates, failover instances sync them via this container.

## Logs

Monitor sync activity:
```bash
docker logs -f traefik-sync
```

## License

MIT
