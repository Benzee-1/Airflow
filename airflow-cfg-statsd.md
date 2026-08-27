# Activer les métriques StatsD dans Airflow 3

À appliquer sur les 4 serveurs Airflow, dans `airflow.cfg` (ou variables d'environnement
équivalentes, à préférer si Airflow tourne en conteneur) :

```ini
[metrics]
statsd_on = True
statsd_host = localhost
statsd_port = 8125
statsd_prefix = airflow
```

Équivalent en variables d'environnement (utile si Airflow est lancé via systemd/Docker avec
un fichier `vars` comme c'est déjà l'usage sur `/opt/GOLD/AF/vars`) :

```bash
export AIRFLOW__METRICS__STATSD_ON=True
export AIRFLOW__METRICS__STATSD_HOST=localhost
export AIRFLOW__METRICS__STATSD_PORT=8125
export AIRFLOW__METRICS__STATSD_PREFIX=airflow
```

**Redémarrage requis** : scheduler, dag_processor, triggerer et apiserver doivent être
relancés pour prendre en compte le changement (`statsd_on` est lu au démarrage du processus).

## Vérification

```bash
# Sur le serveur Airflow, après redémarrage du scheduler :
sudo tcpdump -i lo -A 'udp port 8125' -c 5
# On doit voir des paquets StatsD du type : airflow.scheduler_heartbeat:1|c

# Puis côté statsd_exporter (une fois déployé) :
curl -s http://localhost:9102/metrics | grep airflow_scheduler_heartbeat
```

Si rien n'apparaît après 1-2 minutes : vérifier que le process a bien redémarré avec la
nouvelle configuration (`ps aux | grep airflow` puis inspecter les variables d'environnement
du process via `/proc/<pid>/environ`).
