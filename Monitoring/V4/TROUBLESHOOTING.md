# Troubleshooting

## Target absent
`curl -f http://IP:12345/metrics`; `firewall-cmd --list-ports`; `journalctl -u alloy -n 100`.

## Alloy indisponible
`alloy validate /etc/alloy/config.alloy`; `systemctl status alloy`; `ss -lntp | grep 12345`.

## PostgreSQL absent
`grep POSTGRES_DSN /etc/alloy/alloy.env`; `psql "$POSTGRES_DSN" -c 'select 1'`; rechercher `pg_up` dans l'endpoint Alloy.

## Redis absent
`docker ps --filter name=redis`; `redis-cli -p 6378 ping`; rechercher `redis_up`.

## Alertmanager sans email
`docker logs monitoring-alertmanager`; `docker exec monitoring-alertmanager wget -qO- http://host.docker.internal:25 || true`; `journalctl -u postfix -n 100`; `mailq`.

## Dashboard vide
Vérifier la période, datasource Prometheus, variables `environment`/`instance`, puis tester `{job=~".+"}` dans Explore.

## Worker non découvert
`python3 -m json.tool prometheus/targets/workers-stg.json`; inspecter `/api/v1/targets`; vérifier le port 12345 du worker.

## OTLP Airflow absent
Vérifier la variable dans le conteneur Airflow, l'accès au port 9090, les logs Airflow et `curl http://SID1:9090/api/v1/label/service_name/values`.
