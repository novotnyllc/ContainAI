FROM alpine:3.19

RUN adduser -D -H -u 65532 logfw \
    && apk add --no-cache openssl ca-certificates busybox

USER logfw
WORKDIR /

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["touch /var/log/squid/access.log && tail -F /var/log/squid/access.log | openssl s_client -quiet -connect ${BROKER_HOST:-127.0.0.1:4433} -cert /certs/log-client.crt -key /certs/log-client.key -CAfile /certs/log-ca.crt"]
