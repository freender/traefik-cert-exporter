#!/usr/bin/env python3
"""Publish Traefik's ACME certificate into Redis for Traefik's KV provider.

Every INTERVAL seconds: read the certificate for DOMAIN from acme.json, ask the
Sentinels for the current master, and if the master's copy differs, write the
certificate and key in one MULTI/EXEC. The same rule covers exporter start, a
renewal, a Sentinel failover, and a Redis that came back empty.
"""

import base64
import json
import os
import signal
import sys
import time

import redis
from redis.sentinel import Sentinel

HEARTBEAT = "/tmp/exporter.ok"


def log(msg):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {msg}", flush=True)


def env(name, default=None):
    value = os.environ.get(name, default)
    if value is None or value == "":
        sys.exit(f"traefik-cert-exporter: {name} is required")
    return value


def parse_sentinels(spec):
    out = []
    for item in spec.split(","):
        host, _, port = item.strip().rpartition(":")
        out.append((host, int(port)))
    return out


def read_cert(path, resolver, domain):
    """Return (cert_pem, key_pem) for domain, or None when absent."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    for entry in (data.get(resolver) or {}).get("Certificates") or []:
        if (entry.get("domain") or {}).get("main") == domain:
            cert = base64.b64decode(entry["certificate"]).decode()
            key = base64.b64decode(entry["key"]).decode()
            if cert and key:
                return cert, key
    return None


def main():
    acme_path = env("ACME_PATH", "/acme/acme.json")
    resolver = env("RESOLVER", "letsencrypt")
    domain = env("DOMAIN")
    sentinels = parse_sentinels(env("REDIS_SENTINEL_ADDRS"))
    master_name = env("REDIS_SENTINEL_MASTER", "traefik")
    prefix = env("KEY_PREFIX", "traefik/tls/certificates/0").rstrip("/")
    interval = float(env("INTERVAL", "5"))
    password = os.environ.get("REDIS_PASS") or None

    cert_key, key_key = f"{prefix}/certFile", f"{prefix}/keyFile"
    sentinel = Sentinel(sentinels, socket_timeout=3)
    master = sentinel.master_for(
        master_name, password=password, socket_timeout=3, decode_responses=True
    )

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    log(f"watching {acme_path} ({resolver}, {domain}) -> {prefix} on '{master_name}'")

    last_error = None
    while True:
        try:
            pair = read_cert(acme_path, resolver, domain)
            if pair is None:
                raise LookupError(f"no certificate for {domain} in {acme_path}")
            cert, key = pair
            have_cert, have_key = master.mget(cert_key, key_key)
            if have_cert != cert or have_key != key:
                pipe = master.pipeline(transaction=True)
                pipe.set(cert_key, cert)
                pipe.set(key_key, key)
                pipe.execute()
                log(f"published certificate ({len(cert)} bytes) to {prefix}")
            if last_error is not None:
                log("recovered")
                last_error = None
            with open(HEARTBEAT, "w", encoding="utf-8") as fh:
                fh.write(str(time.time()))
        except (OSError, ValueError, LookupError, KeyError, redis.RedisError) as exc:
            # A failed read is a retry, never a reason to write.
            msg = f"{type(exc).__name__}: {exc}"
            if msg != last_error:
                log(f"retrying: {msg}")
                last_error = msg
        time.sleep(interval)


if __name__ == "__main__":
    main()
