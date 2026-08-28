# Résumé de solution

Prometheus, Grafana, Alertmanager et cAdvisor fonctionnent via Docker Compose sur SRAI-AIR-SID1. Alloy 1.19.2 est installé en RPM/systemd sur toutes les VMs. Alloy collecte localement puis envoie les métriques par Remote Write vers Prometheus. Prometheus scrappe aussi le port 12345 pour vérifier la disponibilité de chaque agent. Les métriques Airflow OpenTelemetry sont envoyées directement au récepteur OTLP HTTP de Prometheus sur 9090.

## Sécurité

- Remplacer tous les `CHANGE_ME` avant démarrage.
- Autoriser 12345 uniquement depuis 10.240.129.104.
- Restreindre 3000, 9090 et 9093 aux réseaux d'administration.
- Ne pas placer de secrets dans Git; fichiers secrets en mode 0600.
- Activer TLS ou un reverse proxy authentifié si les flux sortent du réseau privé.
- Sauvegarder les volumes Grafana et Prometheus.

## Limites assumées

- La découverte Workers utilise File-SD, simple et déterministe. Azure SD nécessite les informations abonnement, tenant, resource group et une identité Azure, non fournies.
- Les métriques détaillées Celery de file et de tâches nécessitent instrumentation Airflow/Celery ou Flower exporter. Le fichier Worker supervise le processus sans multiplier les exporteurs.
- Les métriques de santé Airflow dépendent des noms émis par Airflow 3.2. Vérifier les séries réellement ingérées avant d'activer les règles associées.
