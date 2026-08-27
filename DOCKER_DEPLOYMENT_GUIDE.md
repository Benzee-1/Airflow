# Guide de Déploiement Docker - Monitoring Prometheus (4 serveurs Airflow)

## 🎯 Architecture

**Serveurs Airflow supervisés:**
- **Stage/Qualif:** SRAI-AIR-SIT1 (10.240.129.99) et SRAI-AIR-SIT2 (10.240.129.100)
- **Production:** SRAI-AIR-SIP1 (10.240.129.101) et SRAI-AIR-SIP2 (10.240.129.102)

**Stack central (Docker Compose):**
- Prometheus :9090 (TSDB)
- Grafana :3000 (Dashboards)
- AlertManager :9093 (Notifications)
- Postfix :25 (Local SMTP relay)

---

## 📋 Prérequis

### Sur le serveur central (où tourneront les containers)
```bash
# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
bash get-docker.sh
usermod -aG docker $USER
newgrp docker

# Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Vérifier
docker --version
docker-compose --version
```

### Sur chaque serveur Airflow (4 serveurs)
```bash
# Exigences: Python 3, pip3, wget, curl
which python3 pip3 wget curl

# Au minimum 20GB disque libre
df -h /

# Ports disponibles: 9100, 9187, 6379, 8888
netstat -tlnp 2>/dev/null | grep -E ":(9100|9187|6379|8888)"
```

---

## 🚀 Phase 1: Préparation du Serveur Central

### 1.1 Créer la structure de dossiers

```bash
# Créer le répertoire de déploiement
mkdir -p /opt/prometheus-stack
cd /opt/prometheus-stack

# Structure:
# /opt/prometheus-stack/
# ├── docker-compose.yml
# ├── prometheus.yml
# ├── alertmanager.yml
# ├── grafana-datasources.yml
# ├── grafana-dashboards.yml
# └── rules/
#     └── airflow_alerts.yml
```

### 1.2 Copier les fichiers de configuration

```bash
# À partir de votre machine locale ou du repo:
scp docker-compose.yml root@<central-server>:/opt/prometheus-stack/
scp prometheus_4servers.yml root@<central-server>:/opt/prometheus-stack/prometheus.yml
scp alertmanager_postfix.yml root@<central-server>:/opt/prometheus-stack/alertmanager.yml
scp grafana-datasources.yml root@<central-server>:/opt/prometheus-stack/
scp airflow_celery_alerts.yml root@<central-server>:/opt/prometheus-stack/rules/
```

### 1.3 Adapter les permissions

```bash
cd /opt/prometheus-stack

# Créer les dossiers manquants
mkdir -p rules grafana/dashboards

# Permissions
chmod 755 . rules
chmod 644 *.yml
chmod 644 rules/*.yml
```

### 1.4 Vérifier les configurations YAML

```bash
# Prometheus
docker run --rm -v $(pwd)/prometheus.yml:/prometheus.yml \
  prom/prometheus:v2.52.0 \
  promtool check config /prometheus.yml

# AlertManager
docker run --rm -v $(pwd)/alertmanager.yml:/alertmanager.yml \
  prom/alertmanager:v0.27.0 \
  amtool check-config /alertmanager.yml
```

---

## 🐳 Phase 2: Lancer le Stack Docker

### 2.1 Démarrer les containers

```bash
cd /opt/prometheus-stack

# Démarrer en arrière-plan
docker-compose up -d

# Vérifier le statut
docker-compose ps

# Résultat attendu:
# NAME              STATUS              PORTS
# prometheus        Up (healthy)        0.0.0.0:9090->9090/tcp
# alertmanager      Up (healthy)        0.0.0.0:9093->9093/tcp
# grafana           Up (healthy)        0.0.0.0:3000->3000/tcp
# postfix           Up (healthy)        0.0.0.0:25->25/tcp
```

### 2.2 Vérifier les logs

```bash
# Tous les logs
docker-compose logs -f

# Logs spécifiques
docker-compose logs -f prometheus
docker-compose logs -f grafana
docker-compose logs -f alertmanager
docker-compose logs -f postfix
```

### 2.3 Vérifier l'accessibilité

```bash
# Prometheus
curl -s http://localhost:9090/-/healthy

# AlertManager
curl -s http://localhost:9093/-/healthy

# Grafana
curl -s http://localhost:3000/api/health

# Postfix (sur le container)
docker-compose exec postfix postfix status
```

---

## 📊 Phase 3: Déployer les Exporters sur les 4 Serveurs Airflow

### 3.1 Installation sur chaque serveur

```bash
# Sur chaque serveur (SIT1, SIT2, SIP1, SIP2):
cd /tmp
wget https://<your-repo>/install_exporters_airflow.sh
bash install_exporters_airflow.sh
```

### 3.2 Vérifier l'installation

```bash
# Sur chaque serveur:
curl -s http://localhost:9100/metrics | head -10
curl -s http://localhost:9187/metrics | head -10
curl -s http://localhost:8888/metrics | head -10
```

### 3.3 Script de vérification globale

```bash
#!/bin/bash
SERVERS=(
  "10.240.129.99:SIT1"
  "10.240.129.100:SIT2"
  "10.240.129.101:SIP1"
  "10.240.129.102:SIP2"
)

for server in "${SERVERS[@]}"; do
  ip=${server%:*}
  name=${server#*:}
  echo "Checking $name ($ip)..."
  
  for port in 9100 9187 6379 8888; do
    if curl -s -m 2 http://$ip:$port/metrics > /dev/null 2>&1; then
      echo "  ✓ Port $port"
    else
      echo "  ✗ Port $port"
    fi
  done
done
```

---

## ✅ Phase 4: Vérifier dans Prometheus

```bash
# Ouvrir Prometheus
http://localhost:9090

# Aller à Status → Targets
# Vous devriez voir:
# - airflow-stage: 2 targets UP
# - airflow-prod: 2 targets UP
# - postgresql-stage: 2 targets UP
# - postgresql-prod: 2 targets UP
# - redis-stage: 2 targets UP
# - redis-prod: 2 targets UP
# - celery-stage: 2 targets UP
# - celery-prod: 2 targets UP
# - node-stage: 2 targets UP
# - node-prod: 2 targets UP
# TOTAL: 20 targets UP
```

---

## 📈 Phase 5: Configurer Grafana

### 5.1 Accès initial

```
URL: http://localhost:3000
Login: admin
Password: admin_change_me  (CHANGER IMMÉDIATEMENT!)
```

### 5.2 Changer le mot de passe

Profile → Change Password

### 5.3 Vérifier la datasource Prometheus

Configuration → Data Sources → Prometheus → Test

Résultat attendu: "datasource is working"

### 5.4 Importer les dashboards

Dashboards → Import Dashboard

**IDs recommandés:**
- 12632: Apache Airflow
- 9628: PostgreSQL Database
- 11835: Redis
- 1860: Node Exporter

---

## 📧 Phase 6: Configurer les Notifications Email

### 6.1 Vérifier Postfix

```bash
# Sur le container Postfix:
docker-compose exec postfix postfix status

# Tester le relayage:
docker-compose exec postfix sendmail -t <<EOF
To: test@company.com
Subject: Test email
Body: This is a test

EOF
```

### 6.2 Configurer AlertManager (déjà inclus)

Le fichier `alertmanager.yml` utilise déjà:
- SMTP: postfix:25
- From: alertmanager@airflow.local
- Receivers configurés pour:
  - **Production critical**: airflow-oncall@company.com
  - **Stage critical**: airflow-team@company.com
  - **Warnings**: airflow-team@company.com

**À adapter dans `alertmanager.yml`:**
```yaml
# Remplacer les emails cibles:
- to: 'airflow-oncall@company.com'     # Votre email on-call
- to: 'airflow-team@company.com'       # Votre email équipe
```

### 6.3 Recharger la configuration

```bash
docker-compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
docker-compose restart alertmanager
```

### 6.4 Tester une alerte

```bash
curl -X POST http://localhost:9093/api/v1/alerts \
-H 'Content-Type: application/json' \
-d '[{
  "status": "firing",
  "labels": {
    "alertname": "TestAlert",
    "severity": "critical",
    "environment": "production"
  },
  "annotations": {
    "summary": "Test alert from CLI",
    "description": "Verify email notification is received"
  }
}]'

# Vérifier la réception de l'email
```

---

## 🔍 Commandes Utiles (Docker Compose)

```bash
# Démarrer/Arrêter
docker-compose up -d
docker-compose down
docker-compose restart

# Logs
docker-compose logs -f
docker-compose logs -f <service>
docker-compose logs --tail 50 <service>

# Exécuter des commandes
docker-compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
docker-compose exec alertmanager amtool alert
docker-compose exec grafana grafana-cli admin reset-admin-password newpassword

# Volumes et data
docker-compose volume ls
docker volume rm <volume_name>

# Network
docker-compose exec <service> ping <other_service>
```

---

## 💾 Sauvegarde et Persistance

### Volumes Docker

Les données sont persistées dans:
- `prometheus-data`: /prometheus
- `grafana-data`: /var/lib/grafana
- `alertmanager-data`: /alertmanager

Ces volumes survivent aux redémarrages des containers.

### Backup manuel

```bash
# Sauvegarder les configurations
tar czf backup-config-$(date +%Y%m%d).tar.gz \
  prometheus.yml alertmanager.yml grafana-datasources.yml rules/

# Sauvegarder les données Prometheus
docker run --rm -v prometheus-data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/prometheus-data-$(date +%Y%m%d).tar.gz -C /data .

# Sauvegarder les données Grafana
docker run --rm -v grafana-data:/data \
  -v $(pwd)/backups:/backup \
  alpine tar czf /backup/grafana-data-$(date +%Y%m%d).tar.gz -C /data .
```

---

## 🔧 Maintenance

### Monitorage quotidien

```bash
# Vérifier les services
docker-compose ps

# Vérifier les alertes
curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | {alertname, status, labels}'

# Vérifier les targets Prometheus
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
```

### Mise à jour des images

```bash
# Pull des nouvelles versions
docker-compose pull

# Redémarrer avec les nouvelles images
docker-compose up -d
```

### Recharger la configuration (sans redémarrer)

```bash
# Prometheus
curl -X POST http://localhost:9090/-/reload

# AlertManager (redémarrage obligatoire)
docker-compose restart alertmanager
```

---

## 🐛 Troubleshooting

### Les containers ne démarrent pas

```bash
# Vérifier les logs
docker-compose logs <service>

# Vérifier les ports
netstat -tlnp | grep -E ":(9090|9093|3000|25)"

# Vérifier la syntaxe YAML
docker run --rm -v $(pwd):/work prom/prometheus:v2.52.0 \
  promtool check config /work/prometheus.yml
```

### Targets DOWN dans Prometheus

```bash
# Sur le serveur Airflow, vérifier:
curl http://localhost:9100/metrics  # Node Exporter
curl http://localhost:9187/metrics  # PostgreSQL
curl http://localhost:6379/ping     # Redis (devrait répondre PONG)
curl http://localhost:8888/metrics  # Celery

# Vérifier les services
systemctl status node_exporter
systemctl status postgres_exporter
systemctl status redis_exporter
systemctl status celery_exporter

# Vérifier les ports
netstat -tlnp | grep -E ":(9100|9187|6379|8888)"
```

### Emails non reçus

```bash
# Vérifier la configuration AlertManager
docker-compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

# Vérifier les logs Postfix
docker-compose logs postfix | grep -i "sent\|error\|failed"

# Tester Postfix depuis Prometheus
docker-compose exec prometheus bash -c \
  'echo "Test" | curl smtp://postfix:25 --mail-from test@test.com --mail-rcpt admin@test.com -T -'
```

### Grafana - Datasource Prometheus ne répond pas

```bash
# Vérifier la connectivité entre containers
docker-compose exec grafana ping prometheus

# Vérifier Prometheus
docker-compose exec prometheus curl -s http://localhost:9090/-/healthy
```

---

## 📊 Métriques Collectées

**Par serveur Airflow (4 × 5 sources):**
- Node Exporter: ~50 métriques (CPU, RAM, disque, réseau)
- Airflow Metrics: ~20 métriques (DAGs, tasks, executors)
- PostgreSQL Exporter: ~50 métriques (connexions, cache, replication)
- Redis Exporter: ~30 métriques (mémoire, commandes, clients)
- Celery Exporter: ~20 métriques (tasks, workers, queues)

**Total: ~170 métriques par serveur × 4 = ~680 métriques/min**

---

## ✨ Résumé du Déploiement

| Phase | Étape | Durée | Serveur |
|-------|-------|-------|---------|
| 1 | Préparation centrale | 15 min | Central |
| 2 | Docker Compose up | 5 min | Central |
| 3 | Exporters × 4 serveurs | 30 min | 4 Airflow |
| 4 | Vérification Prometheus | 5 min | Central |
| 5 | Configuration Grafana | 10 min | Central |
| 6 | Notifications email | 10 min | Central |
| **TOTAL** | | **75 min** | |

---

## 🔐 Sécurité

### Recommandations

1. **Changer les mots de passe par défaut**
   ```bash
   # Grafana
   docker-compose exec grafana grafana-cli admin reset-admin-password <new_password>
   ```

2. **Restreindre l'accès réseau**
   ```bash
   # Firewall (ufw)
   ufw allow from 10.240.129.0/24 to any port 9090
   ufw allow from 10.240.129.0/24 to any port 3000
   ufw allow from 10.240.129.0/24 to any port 9093
   ```

3. **Utiliser HTTPS en production**
   - Ajouter un reverse proxy (nginx, traefik)
   - Certificats SSL auto-signés ou Let's Encrypt

4. **Authentification Grafana**
   - LDAP/Active Directory
   - OAuth2

---

## 📚 Documentation Supplémentaire

- [Prometheus Docker Image](https://hub.docker.com/r/prom/prometheus)
- [Grafana Docker Image](https://hub.docker.com/r/grafana/grafana)
- [AlertManager Documentation](https://prometheus.io/docs/alerting/latest/overview/)
- [Postfix SMTP Configuration](http://www.postfix.org/SMTP_AUTH_README.html)

---

**Statut:** Production-Ready  
**Version:** 1.0  
**Date:** 2026-08-27

Bon déploiement ! 🚀
