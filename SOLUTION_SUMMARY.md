# SOLUTION_SUMMARY — Supervision Airflow 3 / Azure

## 1. Vue d'ensemble

Une stack Prometheus/Grafana/AlertManager est déployée en **Docker Compose** sur
`SRAI-AIR-SID1` (10.240.129.104). Elle scrape en pull :

- les **4 serveurs Airflow** (SIT1, SIT2, SIP1, SIP2) : apiserver, scheduler,
  triggerer, dag_processor, PostgreSQL, Redis, Celery worker local, agent Azure,
  métriques système ;
- les **~16 VMs workers Celery** : métriques système + état du service worker +
  état de l'agent Azure (via `node_exporter`), files/tâches Celery capturées
  côté broker (pas besoin d'agent par worker) ;
- **elle-même** (conteneurs Docker, hôte).

## 2. Composants

| Composant | Rôle | Port | Où |
|---|---|---|---|
| Prometheus | Collecte + stockage TSDB | 9090 | SID1 (Docker) |
| Grafana | Dashboards | 3000 | SID1 (Docker) |
| AlertManager | Routage/déduplication alertes → Postfix | 9093 | SID1 (Docker) |
| cAdvisor | Métriques conteneurs du stack monitoring | 8080 | SID1 (Docker) |
| Blackbox Exporter | Health checks HTTP (apiserver `/health`) | 9115 | SID1 (Docker) |
| node_exporter | Métriques système + état systemd | 9100 | Sur **chaque** VM (20) |
| postgres_exporter | Métriques PostgreSQL | 9187 | 4 serveurs Airflow |
| redis_exporter | Métriques Redis (broker) | 9121 | 4 serveurs Airflow |
| statsd_exporter | Traduit les métriques StatsD natives d'Airflow (scheduler heartbeat, durées de tâches, DAG parse time, etc.) en Prometheus | 8125/udp + 9102/http | 4 serveurs Airflow |
| celery-exporter (danihodovic) | Lit l'état des queues/tasks directement dans le broker Redis — **1 instance par environnement**, pas par worker | 9808 | 4 serveurs Airflow (colocalisé, pointe vers le broker local) |
| Postfix | Relais SMTP local (déjà en place) | 25 | SID1 |

## 3. Flux

```
[Airflow servers ×4]──node_exporter/postgres_exporter/redis_exporter/statsd_exporter/celery-exporter──┐
[Worker VMs ×16]──────node_exporter (système + état service celery-worker + agent Azure)───────────────┤
[SID1 lui-même]───────node_exporter + cAdvisor─────────────────────────────────────────────────────────┤
                                                                                                          ▼
                                                                                                    Prometheus (scrape + règles)
                                                                                                          │
                                                                                                          ▼
                                                                                                    AlertManager (routage sévérité)
                                                                                                          │
                                                                                                          ▼
                                                                                                Postfix local (SID1:25) ── mail ──► destinataires
                                                                                                          
Prometheus ◄── datasource ── Grafana (dashboards stage/prod)
```

## 4. Choix techniques clés

- **Métriques Airflow 3** : Airflow n'expose pas nativement un endpoint
  `/metrics` Prometheus fiable. On active `AIRFLOW__METRICS__STATSD_ON=True`
  et on scrape via `statsd_exporter` — approche officiellement supportée,
  indépendante de la version d'Airflow.
- **Celery** : plutôt qu'un exporter par worker (16 agents à maintenir),
  `celery-exporter` interroge directement le broker Redis de chaque
  environnement. Un seul exporter par environnement suffit pour les métriques
  de queue/tâches. Chaque worker reste supervisé individuellement au niveau
  système/process via `node_exporter` (collector `systemd`).
- **Agent Azure** : pas de métriques Prometheus natives. Supervisé via le
  collector `systemd` de `node_exporter` (état du service, ex.
  `walinuxagent.service` / `azuremonitoragent.service`).
- **Découverte des workers** : `file_sd_configs` avec un fichier JSON
  (`prometheus/targets/workers.json`) rechargé automatiquement par Prometheus
  sans redémarrage — évite Consul, adapté à un existant Azure IaaS sans VMSS.
- **Email** : AlertManager relaie via Postfix local (`localhost:25`), sans
  authentification ni TLS sortant — aucun SMTP externe.
- **Environnements** : chaque cible porte un label `env: stage|prod` utilisé
  dans les règles d'alerte et les dashboards Grafana.

## 5. Points d'attention

- `statsd_exporter` nécessite un fichier de mapping (`statsd_mapping.yml`,
  fourni) pour convertir proprement les noms de métriques Airflow.
- `celery-exporter` doit être configuré avec l'URL du broker Redis
  (`redis://:<password>@localhost:6379/0`) — vérifier si Redis est protégé
  par mot de passe/ACL.
- Le fichier `workers.json` est **à tenir à jour** (ajout/retrait de VMs
  workers) — un script `remote-exporters/update_workers_sd.sh` est fourni
  pour le régénérer depuis un inventaire simple.
- Ports à ouvrir uniquement depuis l'IP de SID1 vers les cibles (NSG Azure) :
  9100, 9187, 9121, 9102, 9808.
- Grafana : mot de passe admin à définir via variable d'environnement, pas de
  valeur en dur en configuration versionnée.

## 6. Contenu du livrable

```
airflow-monitoring/
├── SOLUTION_SUMMARY.md
├── docker-compose.yml
├── prometheus/
│   ├── prometheus.yml
│   ├── statsd_mapping.yml
│   ├── rules/alerts.yml
│   └── targets/workers.json
├── alertmanager/alertmanager.yml
├── blackbox/blackbox.yml
├── grafana/provisioning/datasources/datasource.yml
├── remote-exporters/
│   ├── install_node_exporter.sh
│   ├── airflow-servers-docker-compose.yml
│   ├── airflow-cfg-statsd.md
│   └── update_workers_sd.sh
├── DEPLOYMENT_GUIDE.md
├── GRAFANA_DASHBOARDS.md
└── TROUBLESHOOTING.md
```
