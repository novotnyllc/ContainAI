FROM alpine:3.19

RUN adduser -D -H -u 65532 logfw \
    && apk add --no-cache socat ca-certificates busybox

USER logfw
WORKDIR /

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["tail -F /var/log/squid/access.log 2>/dev/null | socat -u - OPENSSL:${BROKER_HOST:-127.0.0.1}:${BROKER_PORT:-4433},cert=/certs/log-client.crt,key=/certs/log-client.key,cafile=/certs/log-ca.crt,verify=1"]
