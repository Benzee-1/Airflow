[[_TOC_]]
#   <span style="color:blue;font-weight:bold">SOLUTION_SUMMARY — Supervision centralisée Airflow V3</span>
---

## Vue d'ensemble

Une stack de supervision unique, hébergée sur **SRAI-AIR-SID1** (`10.240.129.104`) via Docker Compose, centralise les métriques de l'ensemble de l'infrastructure Airflow 3 : 4 serveurs Airflow (stage + prod), ~16 workers Celery, et la stack de supervision elle-même. **Grafana Alloy** est l'agent unique de collecte partout : installé nativement (systemd) sur SID1 et les 4 serveurs Airflow, en conteneur Docker sur les workers.

## Architecture des flux

```
                     ┌─────────────────────────────────────────┐
                     │        SRAI-AIR-SID1 (Docker)            │
                     │  ┌───────────┐ ┌─────────┐ ┌──────────┐ │
     remote_write    │  │Prometheus │ │ Grafana │ │AlertMgr  │ │
   ┌────────────────►│  │  :9090    │ │  :3000  │ │  :9093   │ │
   │                 │  └─────┬─────┘ └─────────┘ └────┬─────┘ │
   │  self-health     │        │  file_sd (workers.json) │      │
   │  scrape (:12345) │        │                          │ SMTP (localhost:25)
   │  ◄───────────────┤        │                          ▼      │
   │                 │  ┌──────┴───┐                 ┌─────────┐ │
   │                 │  │ cAdvisor │                 │ Postfix │ │
   │                 │  └──────────┘                 │ (host)  │ │
   │                 └─────────────────────────────────────────┘
   │
   │   push (metrics)            push (metrics)             push (metrics)
   │
┌──┴──────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│ Alloy (host/systemd)│   │ Alloy (host/systemd)  │   │ Alloy (Docker)        │
│ SIT1/SIT2/SIP1/SIP2 │   │  ...same, x4 hosts    │   │ ~16 Celery workers    │
│ + node/system        │  │                       │   │ + node/system         │
│ + Postgres exporter   │  │                       │   │ + Celery/OTEL bridge  │
│ + Redis exporter      │  │                       │   │ + cAdvisor            │
│ + OTLP bridge (Airflow│  │                       │   └──────────────────────┘
│   metrics via OTel)   │  │                       │
│ + cAdvisor (sidecar)  │  │                       │
└───────────────────────┘  └───────────────────────┘
```

**Métriques : PUSH, pas PULL.** Chaque Alloy envoie ses métriques (système, Postgres, Redis, Airflow/OTel, Celery) directement vers Prometheus via `remote_write` — c'est le fonctionnement natif d'Alloy et cela résout élégamment la contrainte "les workers n'ont pas d'IP fixe" : un worker qui démarre commence à pousser des données immédiatement, sans attendre d'être découvert.

**Découverte des workers : PULL, pour la santé de l'agent uniquement.** Prometheus scrape en plus le port `:12345` (auto-exposé par Alloy, métriques internes de l'agent) de chaque worker via un fichier `file_sd` (`workers.json`) régénéré par `scripts/update_worker_sd.sh` à partir de votre inventaire (CMDB, Ansible, etc.). C'est ce qui alimente l'alerte "agent injoignable" (`AlloyTargetDown`) et répond au livrable "stratégie de découverte dynamique des workers".

## Composants et rôles

| Composant | Où | Rôle |
|---|---|---|
| Prometheus | SID1 (Docker) | Stockage des métriques (30j), évaluation des règles d'alerte, réception `remote_write` |
| Grafana | SID1 (Docker) | Dashboards |
| AlertManager | SID1 (Docker) | Routage et déduplication des alertes, envoi mail via Postfix local |
| Postfix | SID1 (host, déjà en place) | Relais SMTP local uniquement, aucune modification du relais externe |
| cAdvisor | SID1 + 4 serveurs Airflow + workers | Métriques par conteneur Docker |
| Grafana Alloy | Tous les nœuds (~21 avec SID1) | Agent unique : node/system + Postgres + Redis + OTLP (Airflow/Celery) |

## Points d'attention

- **Airflow OTel** : nécessite `pip install 'apache-airflow[otel]'` dans l'image custom `airflow-custom:3.2.0` et l'activation `[metrics] otel_on = True` dans `airflow.cfg` sur chaque composant (voir guide, section 4). C'est expérimental côté Airflow — à valider en stage avant la prod.
- **Protocole OTLP (gRPC vs HTTP)** : Airflow n'expose pas de réglage explicite du protocole ; Alloy écoute les deux (4317/4318). Si aucune métrique n'apparaît après activation, c'est le premier point à vérifier (voir Troubleshooting).
- **Azure Agent** : Alloy n'a pas de composant natif pour l'Azure Monitor Agent ; un script + timer systemd (`check_azure_agent.sh`) expose son statut via le collecteur textfile, lu par l'exporter unix.
- **Pipeline Azure DevOps "TO BE COMPLETED"** (distribution du fichier `vars`, cf. mémoire du déploiement Airflow) : sans lien avec cette stack de supervision, mais à garder en tête pour la cohérence des IP Postgres/Redis remontées dans les dashboards après un failover.
- **Mot de passe Grafana admin** : `__CHANGE_ME__` dans `docker-compose.yml` est un placeholder à remplacer avant le premier démarrage.
- **Mot de passe exporter_user Postgres** : à créer une fois par instance Postgres (rôle `pg_monitor`), saisi interactivement par `install_alloy_host.sh`.

## Prochaines étapes suggérées

1. Déployer sur stage (SIT1/SIT2) d'abord, valider la chaîne OTel de bout en bout, puis répliquer sur prod.
2. Importer les dashboards Grafana listés en section 5 du guide et vérifier les variables `env`/`host`.
3. Ajuster les seuils d'alerte (`airflow_alerts.rules.yml`) après une semaine de données réelles — les valeurs fournies sont des points de départ raisonnables, pas des vérités absolues pour votre volumétrie.
4. Étendre `scripts/worker_inventory.csv` au fur et à mesure de l'arrivée des ~15 workers restants.
