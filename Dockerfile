# Experimental source-only image: official NetEase UU binaries are never bundled.
FROM alpine:3.22
RUN apk add --no-cache ca-certificates curl util-linux pax-utils \
    && addgroup -S -g 10001 uu \
    && adduser -S -D -H -u 10001 -G uu uu \
    && mkdir -p /opt/uu-helper/scripts /opt/uu-helper/docker /var/lib/uu-wol /run \
    && ln -s /var/lib/uu-wol/runtime /usr/sbin/uu \
    && chown -R 10001:10001 /var/lib/uu-wol
COPY lib/ /opt/uu-helper/lib/
COPY scripts/stage-package.sh /opt/uu-helper/scripts/stage-package.sh
COPY docker/entrypoint.sh /opt/uu-helper/docker/entrypoint.sh
RUN chmod 755 /opt/uu-helper/docker/entrypoint.sh /opt/uu-helper/scripts/stage-package.sh
USER 10001:10001
WORKDIR /var/lib/uu-wol
VOLUME ["/var/lib/uu-wol"]
ENTRYPOINT ["/opt/uu-helper/docker/entrypoint.sh"]
CMD ["run"]
