FROM alpine:latest

RUN apk add --no-cache \
    bash \
    curl \
    openssh-client \
    python3 \
    rsync \
    docker-cli

COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
COPY server.py /server.py
COPY sync.sh /sync.sh
RUN chmod +x /entrypoint.sh /healthcheck.sh /sync.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /healthcheck.sh

CMD ["/entrypoint.sh"]
