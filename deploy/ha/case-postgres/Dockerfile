FROM postgres:15-alpine

ARG BUILD_VERSION=0.1.0
ARG BUILD_ARCH=aarch64

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.source="https://github.com/jamesb131/case-home-assistant" \
    org.opencontainers.image.description="CASE Postgres Home Assistant app"

RUN apk add --no-cache jq

ENV PGDATA=/data/postgres

COPY deploy/ha/case-postgres/run.sh /usr/local/bin/case-postgres-run.sh
RUN chmod +x /usr/local/bin/case-postgres-run.sh

EXPOSE 5432

ENTRYPOINT ["/usr/local/bin/case-postgres-run.sh"]
CMD ["postgres"]
