# Déploiement concis

## 1. SRAI-AIR-SID1

```bash
sudo mkdir -p /opt/monitoring
sudo cp -a monitoring-airflow3/. /opt/monitoring/
cd /opt/monitoring
cp .env.example .env
chmod 600 .env
vi .env
sudo firewall-cmd --permanent --add-port={3000,9090,9093}/tcp
sudo firewall-cmd --reload
docker compose config -q
docker compose pull
docker compose up -d
bash scripts/validate-stack.sh
```

Attendu: quatre conteneurs `Up`, endpoints Prometheus, Alertmanager et Grafana sains.

## 2. Postfix local

Autoriser le subnet Docker dans `mynetworks`, puis:

```bash
sudo postfix check
sudo systemctl restart postfix
echo test | mail -s test operations@company.com
mailq
```

Attendu: pas d'erreur `postfix check`; message livré ou file explicite à diagnostiquer.

## 3. PostgreSQL sur chaque serveur Airflow

Modifier le mot de passe SQL et exécuter dans le conteneur PostgreSQL:

```bash
docker exec -i NOM_CONTENEUR_PG psql -U postgres -d postgres < postgres/01-create-monitoring-user.sql
docker exec NOM_CONTENEUR_PG psql -U prom_exporter -d postgres -c 'select 1'
```

Attendu: une ligne contenant `1`.

## 4. Alloy sur Oracle Linux 8.10

Copier le RPM Alloy 1.19.2, la configuration adaptée et le fichier env, puis lancer `install-alloy-ol8.sh`.

Airflow: `config-airflow.alloy`. Worker: `config-worker.alloy`. SID1: `config-monitoring.alloy`.

```bash
sudo /usr/bin/alloy validate /etc/alloy/config.alloy
sudo systemctl restart alloy
sudo systemctl status alloy --no-pager
bash scripts/validate-node.sh
```

Attendu: validation sans erreur, service actif, endpoint Alloy prêt.

## 5. Redis

Le Redis fourni écoute sur l'hôte en `127.0.0.1:6378`. Si authentification absente, supprimer `redis_password_file` du fichier Alloy. Sinon:

```bash
sudo sh -c 'printf "%s" "MOT_DE_PASSE" > /etc/alloy/secrets/redis_password'
sudo chmod 600 /etc/alloy/secrets/redis_password
redis-cli -p 6378 -a 'MOT_DE_PASSE' ping
```

Attendu: `PONG`.

## 6. Airflow OpenTelemetry

L'endpoint actuellement fourni `:4318/v1/metrics` ne correspond pas à la stack proposée, car aucun récepteur OTLP n'écoute sur 4318. Utiliser le snippet fourni qui cible le récepteur OTLP natif Prometheus:

`http://10.240.129.104:9090/api/v1/otlp`

```bash
docker compose up -d --force-recreate apiserver scheduler triggerer dag_processor
curl -fsS http://10.240.129.104:9090/api/v1/label/service_name/values
```

Attendu: présence de `airflow` après le premier intervalle d'export.

## 7. Workers dynamiques

Mettre à jour `prometheus/targets/workers-stg.json` et `workers-prd.json`. Prometheus recharge File-SD automatiquement.

```bash
python3 -m json.tool prometheus/targets/workers-stg.json >/dev/null
curl -fsS http://127.0.0.1:9090/api/v1/targets | grep alloy-workers
```

Attendu: chaque worker apparaît avec `health=up`.

## 8. Grafana

Se connecter sur le port 3000 avec le compte de `.env`. La datasource Prometheus est provisionnée. Variables conseillées dans les dashboards: `environment`, `instance`, `role`.

## Ports

- Clients vers SID1: 3000/TCP Grafana, 9090/TCP OTLP et Prometheus, 9093/TCP Alertmanager si administration nécessaire.
- SID1 vers VMs: 12345/TCP pour la santé Alloy.
- VMs vers SID1: 9090/TCP pour Remote Write et OTLP Airflow.
- Conteneur Alertmanager vers hôte SID1: 25/TCP Postfix.
- Redis 6378, PostgreSQL 5432: accès local seulement pour Alloy.
- 4318 n'est pas utilisé dans cette variante.
