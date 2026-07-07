FROM node:22-alpine AS web-build

WORKDIR /web
COPY web/package*.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM python:3.11-slim AS runtime

ARG BUILD_VERSION=0.1.0
ARG BUILD_ARCH=aarch64

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    org.opencontainers.image.source="https://github.com/jamesb131/case-home-assistant" \
    org.opencontainers.image.description="CASE Core Home Assistant app"

ENV PYTHONUNBUFFERED=1
ENV GOOGLE_DIR=/data/google

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx ca-certificates bash \
    && rm -f /etc/nginx/sites-enabled/default \
    && rm -rf /var/lib/apt/lists/*

COPY api/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY api/app /app/app
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=web-build /web/dist /usr/share/nginx/html
COPY deploy/ha/case-core/case-ha-env.py /usr/local/bin/case-ha-env.py
COPY deploy/ha/case-core/run.sh /usr/local/bin/case-run.sh

RUN chmod +x /usr/local/bin/case-run.sh \
    && mkdir -p /data/google /run/nginx /var/log/nginx

EXPOSE 80 8000

CMD ["/usr/local/bin/case-run.sh"]
