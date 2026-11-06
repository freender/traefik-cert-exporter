# traefik-cert-exporter

Publishes the certificate from one Traefik's ACME `acme.json` into Redis, so every
Traefik reading the same Redis through its KV provider serves the identical certificate.
Only the issuing Traefik runs ACME. Other Traefiks need no resolver and no `acme.json`.

Formerly `traefik-sync`, which copied `acme.json` and `fileConfig.yml` between hosts.

## How it works

Every `INTERVAL` seconds the exporter:

1. Reads the certificate for `DOMAIN` from `acme.json`.
2. Asks the Sentinels for the current master.
3. If the master's copy differs, writes `<KEY_PREFIX>/certFile` and `<KEY_PREFIX>/keyFile`
   as inline PEM in one `MULTI/EXEC`, so a watcher never sees a new cert with the old key.

That one rule covers exporter start, an ACME renewal, a Sentinel failover, and a Redis that
came back empty. A failed read or write is retried and never causes a write. The key never
appears on a command line.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `DOMAIN` | required | `domain.main` of the certificate in `acme.json` |
| `REDIS_SENTINEL_ADDRS` | required | Comma-separated `host:port` Sentinels |
| `REDIS_SENTINEL_MASTER` | `traefik` | Sentinel master name |
| `REDIS_PASS` | none | Redis password (Sentinels themselves are unauthenticated) |
| `ACME_PATH` | `/acme/acme.json` | Path to `acme.json` inside the container |
| `RESOLVER` | `letsencrypt` | Certificate resolver name in `acme.json` |
| `KEY_PREFIX` | `traefik/tls/certificates/0` | Redis key prefix Traefik reads the cert from |
| `INTERVAL` | `5` | Seconds between reconciles; bounds the gap after Redis loses the key |

The image runs as `1000:1000`; `acme.json` must be readable by that user. The healthcheck
fails when no reconcile has succeeded for 60 seconds.

See [docker-compose.example.yml](docker-compose.example.yml).

## Traefik side

- Issuer: keeps its `certificatesResolvers` and entrypoint `certResolver`/`domains`.
- Every other Traefik: entrypoint `http.tls: {}`, no resolver, no `acme.json`, and the
  Redis provider pointed at the same Sentinels.
