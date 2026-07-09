FROM nginx:1.27-alpine

ARG BUILD_VERSION=0.1.0
ARG BUILD_ARCH=aarch64

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.source="https://github.com/jamesb131/case-home-assistant" \
    org.opencontainers.image.description="CASE HTTPS Proxy Home Assistant app"

RUN apk add --no-cache jq

COPY deploy/ha/case-https-proxy/run.sh /usr/local/bin/case-https-proxy-run.sh
RUN chmod +x /usr/local/bin/case-https-proxy-run.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/case-https-proxy-run.sh"]
