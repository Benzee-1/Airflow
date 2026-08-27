# DEPLOYMENT_GUIDE — Procédure de déploiement pas à pas

## 1. Prérequis

**Sur `SRAI-AIR-SID1` (10.240.129.104)**
- Docker Engine ≥ 24.x + plugin Docker Compose v2 (`docker compose version`)
- Postfix déjà installé et écoutant sur `127.0.0.1:25` (confirmer : `ss -tlnp | grep :25`)
- Ports à ouvrir en entrée (firewalld/NSG Azure) : `3000` (Grafana, accès utilisateurs),
  `9090`/`9093` (accès admin uniquement, à restreindre si possible)

**Sur les 4 serveurs Airflow + ~16 workers**
- Ports à ouvrir en entrée, **uniquement depuis l'IP de SID1** (10.240.129.104/32) :
  `9100` (tous), et sur les 4 serveurs Airflow uniquement : `9187`, `9121`, `9102`, `9808`,
  `8080` (apiserver, déjà probablement ouvert)
- Docker Engine requis sur les 4 serveurs Airflow (pour postgres/redis/statsd/celery exporters)
- Pas de Docker requis sur les workers (node_exporter en binaire systemd)
- Compte PostgreSQL en lecture seule dédié à la supervision sur chaque instance :
  ```sql
  CREATE USER monitoring_ro WITH PASSWORD '...';
  GRANT pg_monitor TO monitoring_ro;
  ```

## 2. Installation du serveur de supervision (SID1)

```bash
cd /opt
git clone <votre-repo>/airflow-monitoring.git   # ou copier l'arborescence livrée
cd airflow-monitoring
mkdir -p secrets
echo -n "changeme-strong-password" > secrets/grafana_admin_password.txt
chmod 600 secrets/grafana_admin_password.txt

docker compose up -d
docker compose ps        # les 6 conteneurs doivent être "healthy"/"running"
```

Vérification rapide :
```bash
curl -s http://localhost:9090/-/healthy      # Prometheus
curl -s http://localhost:9093/-/healthy      # Alertmanager
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/login   # Grafana -> 200
```

## 3. Déploiement des exporters sur les 4 serveurs Airflow

Sur **chaque** serveur (SIT1, SIT2, SIP1, SIP2) :

```bash
# 1. node_exporter (systemd natif)
scp remote-exporters/install_node_exporter.sh <serveur>:/tmp/
ssh <serveur> "sudo bash /tmp/install_node_exporter.sh"

# 2. Activation StatsD côté Airflow (voir remote-exporters/airflow-cfg-statsd.md)
#    -> éditer airflow.cfg ou /opt/GOLD/AF/vars, puis redémarrer scheduler/dag_processor/triggerer/apiserver

# 3. Exporters conteneurisés (postgres/redis/statsd/celery)
scp remote-exporters/airflow-servers-docker-compose.yml <serveur>:/opt/monitoring/docker-compose.yml
scp prometheus/statsd_mapping.yml <serveur>:/opt/monitoring/../prometheus/statsd_mapping.yml
ssh <serveur> "cd /opt/monitoring && \
  PG_MONITORING_PASSWORD='...' REDIS_PASSWORD='...' docker compose up -d"
```

Vérification par serveur :
```bash
curl -s http://<serveur>:9100/metrics | head -3     # node_exporter
curl -s http://<serveur>:9187/metrics | grep pg_up  # postgres_exporter
curl -s http://<serveur>:9121/metrics | grep redis_up
curl -s http://<serveur>:9102/metrics | grep airflow_
curl -s http://<serveur>:9808/metrics | grep celery_
```

## 4. Déploiement sur les ~16 VMs workers

Pour chaque worker :
```bash
scp remote-exporters/install_node_exporter.sh <worker>:/tmp/
ssh <worker> "sudo bash /tmp/install_node_exporter.sh"
```

Automatisable en boucle simple si vous avez déjà un inventaire (adapter à vos outils —
Ansible n'est pas obligatoire) :
```bash
while read -r ip; do
  scp remote-exporters/install_node_exporter.sh "${ip}:/tmp/"
  ssh "${ip}" "sudo bash /tmp/install_node_exporter.sh"
done < workers_ips.txt
```

Puis déclarer les workers dans le fichier de découverte :
```bash
cd remote-exporters
./update_workers_sd.sh workers_inventory.csv
# Prometheus recharge automatiquement /etc/prometheus/targets/workers.json (file_sd, refresh 1m)
```

## 5. Configuration de Postfix (relais local, sans SMTP externe)

Sur `SRAI-AIR-SID1`, vérifier/ajuster `/etc/postfix/main.cf` pour autoriser le relais
depuis Docker (le réseau bridge Docker par défaut est `172.17.0.0/16`, à adapter) :

```ini
inet_interfaces = loopback-only, 172.17.0.1
mynetworks = 127.0.0.0/8, 172.16.0.0/12
```

```bash
systemctl restart postfix
ss -tlnp | grep :25
```

## 6. Vérification de bout en bout

```bash
# 1. Toutes les cibles sont UP dans Prometheus
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance_name, health}'

# 2. Valider la syntaxe avant tout déploiement
docker run --rm -v $(pwd)/prometheus:/prom prom/prometheus:v2.55.1 \
  promtool check config /prom/prometheus.yml

docker run --rm -v $(pwd)/alertmanager:/am prom/alertmanager:v0.27.0 \
  amtool check-config /am/alertmanager.yml

# 3. Déclencher une alerte de test (silence puis désactivation) pour valider l'envoi mail
curl -H "Content-Type: application/json" -d '[{
  "labels": {"alertname": "TestAlert", "severity": "warning", "env": "stage", "instance_name": "TEST"}
}]' http://localhost:9093/api/v2/alerts

# vérifier la réception dans la file Postfix
mailq
tail -f /var/log/maillog
```

## 7. Rechargement à chaud (après modification de config)

```bash
# Prometheus (scrape_configs, rules) — sans redémarrage grâce à --web.enable-lifecycle
curl -X POST http://localhost:9090/-/reload

# Alertmanager
curl -X POST http://localhost:9093/-/reload
```

## 8. Sécurité de base

- Grafana : mot de passe admin injecté via Docker secret (jamais en clair dans le repo),
  `GF_USERS_ALLOW_SIGN_UP=false`.
- Ports `9090`/`9093`/`9100`/`9187`/`9121`/`9102`/`9808` : jamais exposés publiquement,
  filtrés par NSG Azure/firewalld à l'IP de SID1 uniquement.
- Seul `3000` (Grafana) et éventuellement `443` derrière un reverse proxy sont exposés
  aux utilisateurs finaux.
- Séparer les credentials PostgreSQL/Redis de supervision (lecture seule) des comptes
  applicatifs Airflow.
