# SOLUTION_SUMMARY.md

## 1. Décision d'architecture

Plateforme centralisée sur **SRAI-AIR-SID1 (10.240.129.104)**, déployée avec Docker Compose.

```text
Airflow 3 (SIT1/SIT2/SIP1/SIP2 et workers)
  | OTLP/HTTP 4318 (métriques Airflow natives)
  v
OpenTelemetry Collector central :4318
  | exposition Prometheus :8889/metrics
  v
Prometheus :9090 ---> Alertmanager :9093 ---> Postfix hôte 10.240.129.104:25 ---> destinataires
  |
  +-- node_exporter :9100 sur chaque VM
  +-- postgres_exporter :9187 sur les 4 nœuds Airflow
  +-- redis_exporter :9121 sur les 4 nœuds Airflow
  +-- celery-exporter :9808 sur chaque worker/local worker, optionnel et à valider
  +-- Azure Agent textfile collector via node_exporter
  +-- blackbox_exporter :9115 pour API/ports/health
  +-- cAdvisor :8080 sur SID1
  v
Grafana :3000
```

## 2. Choix structurants

1. **Airflow 3 vers OpenTelemetry** : voie principale pour les métriques Airflow. Les composants Airflow doivent avoir l'extra `apache-airflow[otel]` installé.
2. **Collecteur OTEL central** : réception OTLP/HTTP sur 4318, enrichissement via attributs de ressource, exposition Prometheus sur 8889.
3. **Prometheus en pull** pour les exporters Linux, PostgreSQL, Redis, Celery et le collecteur OTEL.
4. **Celery** : exporter séparé conservé comme extension, mais les règles ne supposent aucun nom de métrique Celery non vérifié. Valider les métriques réellement exposées avant d'activer les alertes spécifiques.
5. **Azure Agent** : pas d'exporter universel. Un script local publie l'état du service dans le textfile collector de node_exporter. Adapter le nom du service à `walinuxagent`, `waagent` ou `himds` selon le type d'agent.
6. **Workers** : `file_sd_configs` avec fichiers YAML atomiquement régénérés. C'est simple, auditable et compatible avec Azure DevOps/Ansible.
7. **Sécurité** : Grafana est authentifié. Prometheus et Alertmanager restent sur réseau privé et doivent être filtrés par NSG/firewalld. Le kit n'ajoute pas de faux TLS interne : placer un reverse proxy TLS d'entreprise si une exposition utilisateur est requise.
8. **Postfix** : Alertmanager contacte le Postfix de l'hôte via `host.docker.internal:25`, mappé à la passerelle hôte Compose.

## 3. Versions épinglées dans `.env`

- Prometheus 3.13.2 LTS
- Alertmanager 0.34.0
- Grafana 13.2.0
- OpenTelemetry Collector Contrib 0.159.0
- node_exporter 1.9.1, postgres_exporter 0.17.1, redis_exporter 1.77.0, blackbox_exporter 0.27.0, cAdvisor 0.49.2

Les versions non confirmées par une source officielle dans le présent kit doivent être vérifiées dans votre registre miroir avant production. Exécuter `docker compose pull` puis les validations fournies.

## 4. Limites connues

- Le nom exact des métriques OTEL d'Airflow dépend de la version Airflow et de la traduction OTEL/Prometheus. Le kit alerte de façon certaine sur disponibilité des endpoints et exporters. Les règles métier Airflow doivent être finalisées après observation de `/api/v1/label/__name__/values`.
- L'état de l'Azure Agent est local. La dernière communication avec Azure nécessite Azure Monitor/Resource Graph, non incluse dans le chemin Prometheus local.
- SID1 reste un point unique de panne. Une phase 2 peut ajouter deux Prometheus, deux Alertmanager en cluster, Grafana HA et stockage externe.
