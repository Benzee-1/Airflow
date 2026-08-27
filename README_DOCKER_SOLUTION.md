# 🐳 Solution Docker - Monitoring Prometheus Airflow

**Architecture:** 4 serveurs Airflow + 1 stack Docker Compose central  
**Déploiement:** ~60 minutes  
**Status:** Production-Ready  

---

## 📊 Architecture Simplifiée

```
┌─────────────────────────────────────────┐
│      CENTRAL DOCKER STACK                │
├─────────────────────────────────────────┤
│ Prometheus  │ Grafana  │ AlertManager    │
│  :9090      │  :3000   │  :9093          │
│ (TSDB)      │(Dashboards)(Notifications)│
│             │  Postfix :25               │
│             │ (Email relay)              │
└────────────┬────────────────────────────┘
             │
    ┌────────┴──────────────────┐
    │                           │
┌───┴────┐  ┌──────┐  ┌──────┐ │
│ STAGE  │  │ PROD │  │ FUTURE
│ (2)    │  │ (2)  │  │ WORKERS
└───┬────┘  └───┬──┘  └──────┘
 SIT1,SIT2  SIP1,SIP2
    │          │
    └──────────┴──────────────────────┐
                                      │
                        Exporters:9100,9187,6379,8888
```

---

## 🚀 Quick Start (60 minutes)

### Serveurs supervisés (4)
- **Stage:** SRAI-AIR-SIT1 (10.240.129.99), SRAI-AIR-SIT2 (10.240.129.100)
- **Prod:** SRAI-AIR-SIP1 (10.240.129.101), SRAI-AIR-SIP2 (10.240.129.102)

### Étapes

```bash
# 1. SUR LE SERVEUR CENTRAL (Docker)
mkdir -p /opt/prometheus-stack
cd /opt/prometheus-stack

# Copier les fichiers
scp docker-compose.yml prometheus.yml alertmanager.yml grafana-datasources.yml .
mkdir -p rules
scp airflow_celery_alerts.yml rules/

# Lancer le stack
docker-compose up -d

# Vérifier
curl http://localhost:9090/targets  # Prometheus
http://localhost:3000               # Grafana (admin/admin_change_me)

---

# 2. SUR CHAQUE SERVEUR AIRFLOW (4×)
bash install_exporters_airflow.sh

# Vérifier
curl http://localhost:9100/metrics
```

---

## 📁 Fichiers Livrés

### Configuration (YAML)

| Fichier | Rôle |
|---------|------|
| `docker-compose.yml` | 4 services (Prometheus, Grafana, AlertManager, Postfix) |
| `prometheus_4servers.yml` | Config de scrape pour 4 serveurs Airflow |
| `alertmanager_postfix.yml` | Notifications email via Postfix local |
| `grafana-datasources.yml` | Provisioning datasource Prometheus |

### Scripts

| Fichier | Rôle |
|---------|------|
| `install_exporters_airflow.sh` | Install sur 4 serveurs Airflow |

### Documentation

| Fichier | Rôle |
|---------|------|
| `DOCKER_DEPLOYMENT_GUIDE.md` | Guide complet 6 phases |
| `DOCKER_QUICK_REFERENCE.txt` | Commandes et URLs rapides |

---

## 🐳 Docker Compose - Ce qui tourne

### 4 Containers

```yaml
services:
  prometheus:
    image: prom/prometheus:v2.52.0
    ports: 9090:9090
    storage: 30 jours / 100GB
    
  grafana:
    image: grafana/grafana:10.0.0
    ports: 3000:3000
    
  alertmanager:
    image: prom/alertmanager:v0.27.0
    ports: 9093:9093
    
  postfix:
    image: boky/postfix:latest
    ports: 25:25
    (email relay local)
```

### 3 Volumes (Persistants)

- `prometheus-data`: TSDB (survit aux redémarrages)
- `grafana-data`: Dashboards & datasources
- `alertmanager-data`: État des alertes

---

## 📊 Métriques & Alertes

### Collectes

**Par serveur Airflow (4×):**
- Node Exporter: CPU, RAM, disque, réseau (~50 métriques)
- Airflow: DAGs, tasks, executors (~20 métriques)
- PostgreSQL: Connexions, cache, queries (~50 métriques)
- Redis: Mémoire, clients, commandes (~30 métriques)
- Celery: Tasks, workers, queues (~20 métriques)

**Total: 680 métriques/min (~22/s)**

### Alertes (50+)

**CRITICAL (escalade production):**
- CeleryWorkerDown
- PostgreSQLConnectionPoolExhausted
- RedisMemorySaturation
- LowDiskSpace

**WARNING (5 min batching):**
- HighTaskFailureRate
- PostgreSQLSlowQueries
- HighCPUUsage

**INFO (24h batching):**
- NodeRecentlyRebooted
- DAGExecutionSlow

---

## 📧 Notifications Email

**Via Postfix local (localhost:25)**

Routing automatique:
- **Production Critical** → airflow-oncall@company.com (urgent)
- **Stage Critical** → airflow-team@company.com
- **Warnings** → airflow-team@company.com
- **Info** → airflow-team@company.com (24h digest)

**À adapter dans `alertmanager.yml` avant déploiement**

---

## 🔗 URLs d'Accès

| Service | URL | Login |
|---------|-----|-------|
| **Prometheus** | http://localhost:9090 | - |
| **Grafana** | http://localhost:3000 | admin / admin_change_me |
| **AlertManager** | http://localhost:9093 | - |

### Sous-URLs utiles

```
Prometheus:
  /targets          - État des 4 serveurs
  /alerts           - Alertes actives
  /graph            - Query builder

Grafana:
  /admin/datasources - Prometheus
  /dashboards        - 4 importés (Airflow, PostgreSQL, Redis, Node)
```

---

## ✅ Checklist Déploiement

### Central (15 min)

- [ ] Docker & Docker Compose installés
- [ ] Dossier `/opt/prometheus-stack` créé
- [ ] Fichiers YAML copiés
- [ ] `docker-compose up -d` lancé
- [ ] Tous les containers UP
- [ ] Prometheus targets accessible
- [ ] Grafana accessible
- [ ] Postfix running (email test optionnel)

### 4 Serveurs Airflow (30 min)

- [ ] `install_exporters_airflow.sh` exécuté
- [ ] 4× Node Exporter :9100 UP
- [ ] 4× PostgreSQL Exporter :9187 UP
- [ ] 4× Redis Exporter :6379 UP
- [ ] 4× Celery Exporter :8888 UP

### Vérifications (15 min)

- [ ] Prometheus: 20 targets UP (4 servers × 5 exporters)
- [ ] Grafana: Datasource Prometheus OK
- [ ] Grafana: 4 dashboards importés
- [ ] AlertManager: Configuration OK
- [ ] Email test reçu (optionnel)

---

## 🔧 Commandes Essentielles

```bash
# Démarrer/Arrêter
docker-compose up -d
docker-compose down
docker-compose restart

# Logs & debugging
docker-compose logs -f
docker-compose logs -f prometheus
docker-compose ps

# Vérifier
curl http://localhost:9090/-/healthy
curl http://localhost:9093/-/healthy
curl http://localhost:3000/api/health

# Recharger config (Prometheus)
curl -X POST http://localhost:9090/-/reload

# Dans les containers
docker-compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
docker-compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
```

---

## 🐛 Troubleshooting

### Targets DOWN

```bash
# Sur le serveur Airflow, tester les exporters:
curl http://localhost:9100/metrics  # Node
curl http://localhost:9187/metrics  # PostgreSQL
curl http://localhost:8888/metrics  # Celery

# Vérifier les services
systemctl status node_exporter
systemctl status postgres_exporter
systemctl status celery_exporter

# Vérifier les ports
netstat -tlnp | grep -E ":(9100|9187|6379|8888)"
```

### Emails non reçus

```bash
# Vérifier AlertManager config
docker-compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

# Vérifier Postfix
docker-compose logs postfix | grep -i error
docker-compose exec postfix postfix status
```

### Container ne démarre pas

```bash
# Logs
docker-compose logs <service>

# Vérifier les ports disponibles
netstat -tlnp | grep -E ":(9090|9093|3000|25)"
```

---

## 📈 Scaling & Évolution

### Ajouter d'autres serveurs Airflow

1. Noter l'IP du nouveau serveur
2. Ajouter dans `prometheus.yml` (sous le job correspondant)
3. Exécuter `install_exporters_airflow.sh`
4. Recharger: `curl -X POST http://localhost:9090/-/reload`

### Monitorer d'autres workers

Les scripts sont prêts pour ajouter des "workers" futurs mentionnés dans l'architecture.

---

## 💾 Sauvegarde

### Automatique (via volumes Docker)

Les données Prometheus, Grafana et AlertManager sont dans des volumes persistants.

### Manuel

```bash
# Configurations
tar czf backup-$(date +%Y%m%d).tar.gz prometheus.yml alertmanager.yml rules/

# Données Prometheus
docker run --rm -v prometheus-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/prometheus-$(date +%Y%m%d).tar.gz -C /data .
```

---

## 🔒 Sécurité

### À faire immédiatement

1. **Changer le mot de passe Grafana**
   ```bash
   docker-compose exec grafana grafana-cli admin reset-admin-password <newpwd>
   ```

2. **Restreindre l'accès réseau**
   ```bash
   ufw allow from 10.240.129.0/24 to any port 9090
   ufw allow from 10.240.129.0/24 to any port 3000
   ```

3. **Adapter les emails AlertManager**
   Remplacer `airflow-team@company.com` et `airflow-oncall@company.com` par les vôtres

4. **HTTPS en production**
   Ajouter un reverse proxy (nginx, traefik) avec SSL

---

## 📚 Documentation Complète

Consulter:
- **DOCKER_DEPLOYMENT_GUIDE.md** - Guide détaillé 6 phases
- **DOCKER_QUICK_REFERENCE.txt** - Commandes rapides
- **docker-compose.yml** - Configuration complète

---

## 📊 Capacité & Performance

| Aspect | Valeur |
|--------|--------|
| Serveurs supervisés | 4 |
| Exporters/serveur | 5 |
| Total targets | 20 |
| Métriques/min | ~680 |
| Métriques/sec | ~22 |
| Rétention TSDB | 30 jours |
| Disque max | 100GB |

---

## ✨ Avantages Docker

✅ **Installation simplifiée** - `docker-compose up -d` et c'est prêt  
✅ **Isolation** - Chaque service en container séparé  
✅ **Portabilité** - Fonctionne sur n'importe quel serveur Docker  
✅ **Facilité de backup** - Volumes persistants  
✅ **Scaling** - Ajouter d'autres serveurs en minutes  
✅ **Maintenance** - Mise à jour d'une image, redémarrage propre  

---

## 🎯 Résumé

| Phase | Durée | Étape |
|-------|-------|-------|
| 1 | 10 min | Docker central setup |
| 2 | 5 min | `docker-compose up -d` |
| 3 | 20 min | Exporters × 4 serveurs |
| 4 | 5 min | Prometheus verification |
| 5 | 10 min | Grafana config |
| 6 | 10 min | Email setup |
| **TOTAL** | **60 min** | |

---

## 🚀 Prêt?

1. Lire ce README (5 min)
2. Copier les fichiers
3. Adapter les emails
4. Suivre le guide de déploiement (50 min)
5. Vérifier les targets (5 min)

**Production ready en ~60 minutes!**

---

**Version:** 1.0  
**Date:** 2026-08-27  
**Auteur:** Claude (AI Infrastructure)  
**Status:** ✅ Production-Ready

Bonne chance ! 🐳🚀
