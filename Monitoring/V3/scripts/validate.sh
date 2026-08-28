#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose config >/dev/null
docker run --rm -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:${PROMETHEUS_VERSION:-v3.13.2} promtool check config /etc/prometheus/prometheus.yml
docker run --rm -v "$PWD/prometheus/rules:/rules:ro" prom/prometheus:${PROMETHEUS_VERSION:-v3.13.2} promtool check rules /rules/prometheus.rules.yml
docker run --rm -v "$PWD/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" prom/alertmanager:${ALERTMANAGER_VERSION:-v0.34.0} amtool check-config /etc/alertmanager/alertmanager.yml
docker run --rm -v "$PWD/otel/otel-collector.yml:/etc/otelcol-contrib/config.yaml:ro" otel/opentelemetry-collector-contrib:${OTELCOL_VERSION:-0.159.0} validate --config=/etc/otelcol-contrib/config.yaml
echo OK
