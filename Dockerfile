FROM alpine:latest

RUN apk add --no-cache     bash     openssh-client     rsync     docker-cli

COPY sync.sh /sync.sh
RUN chmod +x /sync.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3     CMD pgrep -f sync.sh || exit 1

ENTRYPOINT ["/sync.sh"]
