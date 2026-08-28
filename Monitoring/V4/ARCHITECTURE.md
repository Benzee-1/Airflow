# Architecture retenue

```text
VM Airflow / Worker                         SRAI-AIR-SID1
Alloy exporters -> scrape -> remote_write -> Prometheus :9090
Airflow OTLP/HTTP -------------------------> Prometheus :9090/api/v1/otlp
Prometheus --------------------------------> Alertmanager :9093
Alertmanager ------------------------------> Postfix hôte :25 -> email
Grafana -----------------------------------> Prometheus
Prometheus --scrape santé Alloy-----------> VM :12345/metrics
```

Le mode Remote Write est retenu pour les métriques collectées par Alloy, car les exporteurs intégrés d'Alloy alimentent une pipeline interne et ne constituent pas un endpoint Prometheus agrégé public. Le port 12345 reste utilisé pour la santé propre d'Alloy.
