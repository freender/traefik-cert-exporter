FROM alpine:latest

RUN apk add --no-cache python3 py3-redis

COPY exporter.py /exporter.py

USER 1000:1000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python3 -c "import os, sys, time; sys.exit(time.time() - os.path.getmtime('/tmp/exporter.ok') > 60)"

CMD ["python3", "-u", "/exporter.py"]
