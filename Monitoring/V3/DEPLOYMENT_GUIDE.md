# Guide de déploiement

## 1. Prérequis et flux

Ouvrir uniquement depuis SID1 vers les cibles : TCP 9100, 9187, 9121, 9808 et port API Airflow. Ouvrir depuis les nœuds Airflow/workers vers SID1 : TCP 4318. Limiter 3000 aux administrateurs; 9090 et 9093 au réseau d'exploitation. Le port 25 reste local/bridge Docker.

## 2. Installation centrale

```bash
sudo install -d -m 0750 /opt/airflow3-monitoring
sudo cp -a airflow3-monitoring/. /opt/airflow3-monitoring/
cd /opt/airflow3-monitoring
cp .env.example .env
chmod 0600 .env
# Modifier mot de passe, destinataire, sender et versions si miroir interne.
set -a; . ./.env; set +a
./scripts/validate.sh
docker compose pull
docker compose up -d
docker compose ps
```

Tests :

```bash
curl -fsS http://127.0.0.1:9090/-/healthy
curl -fsS http://127.0.0.1:9093/-/healthy
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:4318/ || true
curl -fsS http://127.0.0.1:9100/metrics | head
```

## 3. Exporters distants

Sur chaque VM :

```bash
sudo install -d -m 0750 /opt/airflow-exporters
sudo cp remote/docker-compose.exporters.yml /opt/airflow-exporters/docker-compose.yml
sudo cp remote/.env.example /opt/airflow-exporters/.env
sudo chmod 0600 /opt/airflow-exporters/.env
cd /opt/airflow-exporters
# Nœud worker seul
docker compose up -d node-exporter
# Nœud Airflow complet
docker compose --profile airflow-core up -d
curl -fsS http://127.0.0.1:9100/metrics | head
curl -fsS http://127.0.0.1:9187/metrics | head
curl -fsS http://127.0.0.1:9121/metrics | head
```

PostgreSQL : exécuter `remote/postgres-exporter.sql`, placer le secret dans `.env`, puis redémarrer l'exporter. Si TLS est imposé, remplacer `sslmode=disable`.

## 4. Azure Agent

```bash
sudo install -m 0755 remote/azure-agent-metrics.sh /usr/local/sbin/
sudo install -m 0644 remote/azure-agent-metrics.service /etc/systemd/system/
sudo install -m 0644 remote/azure-agent-metrics.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now azure-agent-metrics.timer
sudo systemctl start azure-agent-metrics.service
cat /var/lib/node_exporter/textfile_collector/azure_agent.prom
```

## 5. Airflow 3 OpenTelemetry

Installer l'extra dans le même environnement Python que chaque composant Airflow :

```bash
python -m pip install 'apache-airflow[otel]'
```

Injecter les variables de `remote/airflow-otel.env.example` dans les unités systemd/conteneurs Airflow. Définir `OTEL_RESOURCE_ATTRIBUTES` par VM avec `deployment.environment`, `host.name` et un `service.instance.id` unique. Redémarrer apiserver, scheduler, triggerer, dag-processor et workers.

Tests :

```bash
curl -fsS http://10.240.129.104:8889/metrics | grep -i airflow | head
curl -fsS 'http://10.240.129.104:9090/api/v1/query?query=up%7Bjob%3D%22otel-collector%22%7D'
```

## 6. Workers dynamiques

La source de vérité recommandée est l'inventaire Azure DevOps/Ansible/CMDB. Exporter périodiquement un JSON conforme à `workers.example.json`, puis écrire atomiquement les cibles :

```bash
python3 scripts/generate-workers-file-sd.py workers.json prometheus/file_sd/nodes-workers.yml
curl -X POST http://127.0.0.1:9090/-/reload
```

Créer séparément `celery-workers.yml` sur le même principe si un exporter Celery validé est retenu. Prometheus surveille les fichiers et recharge les cibles sans redémarrage.

## 7. Grafana

Datasource et dashboard initial sont provisionnés. Dashboards communautaires à évaluer, jamais à importer aveuglément : Node Exporter Full ID 1860; PostgreSQL ID 9628; Redis ID 11835. Les IDs peuvent évoluer et les requêtes doivent être adaptées aux noms de jobs/labels du kit.

Variables standard : `environment`, `hostname`, `role`, `job`.

## 8. Test d'alerte de bout en bout

Ajouter temporairement :

```yaml
- alert: AlwaysFiringTest
  expr: vector(1)
  for: 1m
  labels: {severity: warning, environment: test}
  annotations: {summary: Test Alertmanager Postfix}
```

Puis :

```bash
./scripts/validate.sh
curl -X POST http://127.0.0.1:9090/-/reload
docker compose logs --tail=100 alertmanager
journalctl -u postfix --since '-10 min'
```

Retirer immédiatement la règle de test et recharger.

## 9. Troubleshooting

- **Target DOWN** : `curl` depuis SID1, puis `ss -lntp`, firewall/NSG, route et logs du conteneur.
- **Pas de métriques Airflow** : vérifier extra `otel`, variables sur chaque processus, accès TCP 4318 et logs `otel-collector`.
- **OTEL refuse la configuration** : lancer la commande `validate` du script avant démarrage.
- **Email absent** : vérifier `host.docker.internal:25`, `mynetworks`, file Postfix avec `mailq`, et logs Postfix/Alertmanager.
- **Postgres `pg_up 0`** : tester la chaîne `DATA_SOURCE_NAME`, rôle `pg_monitor`, `pg_hba.conf`, TLS et mot de passe.
- **Redis `redis_up 0`** : vérifier AUTH/ACL, URI, bind/protected-mode et accès local.
- **Azure metric absente** : vérifier timer, fichier `.prom`, permissions et `node_textfile_scrape_error`.
- **Worker non découvert** : vérifier YAML/JSON, droits du volume en lecture et page `/service-discovery` de Prometheus.
- **Dashboard vide** : inspecter les labels réels dans Explore; ne pas supposer les noms de métriques Airflow traduits.
