[[_TOC_]]
#   <span style="color:blue;font-weight:bold">Overview</span>
---
This document describes the deployment of a centralized supervision platform for the Apache Airflow 3 infrastructure: Prometheus, Grafana, AlertManager and cAdvisor on a dedicated Docker Compose stack (**SRAI-AIR-SID1**), with **Grafana Alloy** as the single collection agent everywhere else — installed on the host (systemd) on the 4 Airflow servers, and in Docker on the Celery worker VMs. Metrics are **pushed** by every Alloy to Prometheus (`remote_write`); a separate, lightweight **pull** path via file-based service discovery is used only to monitor whether each worker's agent itself is alive. See `SOLUTION_SUMMARY.md` for the executive summary and architecture diagram.

All the files referenced below (`docker-compose.yml`, `prometheus.yml`, `alertmanager.yml`, `.alloy` configs, scripts) are provided as standalone files alongside this guide — this document explains what each one does and how to wire them together; it does not repeat their full content inline except where a short excerpt helps.

#   <span style="color:blue;font-weight:bold">1. Schéma d'architecture</span>
---
See `SOLUTION_SUMMARY.md` for the annotated ASCII diagram. In one sentence: every node (4 Airflow servers, ~16 workers, SID1 itself) runs one Grafana Alloy instance that collects locally and **pushes** everything to the central Prometheus via `remote_write`; Prometheus additionally **pulls** each Alloy's own `:12345` self-metrics endpoint (static for the 4 known Airflow servers, file-based service discovery for the workers) purely to detect a dead agent.

Why push instead of pull for the actual metrics: it removes the "workers have no fixed IP" problem entirely for data collection — a new worker starts reporting the moment Alloy starts, with no discovery lag — while still satisfying the requested file-based-SD strategy for the one thing that genuinely needs it (agent health).

#   <span style="color:blue;font-weight:bold">2. Arborescence du projet Docker Compose (SRAI-AIR-SID1)</span>
---
Deploy the monitoring stack under `/opt/GOLD/MON/`, mirroring the existing `/opt/GOLD/AF/` convention used for Airflow itself:

```
/opt/GOLD/MON/
├── docker-compose.yml
├── prometheus/
│   ├── prometheus.yml
│   ├── rules/
│   │   └── airflow_alerts.rules.yml
│   └── file_sd/
│       ├── workers.json
│       └── workers_cadvisor.json
├── alertmanager/
│   └── alertmanager.yml
├── grafana/
│   └── provisioning/
│       ├── datasources/prometheus.yml
│       └── dashboards/dashboards.yml
├── cadvisor/                      (on SID1 itself, cadvisor runs inside docker-compose.yml above — no separate folder needed)
└── scripts/
    ├── install_alloy_host.sh
    ├── check_azure_agent.sh
    ├── update_worker_sd.sh
    └── worker_inventory.csv       (generated on first run of update_worker_sd.sh)
```

On each of the 4 Airflow servers, under `/opt/GOLD/MON/`:
```
/opt/GOLD/MON/
├── cadvisor/
│   └── docker-compose.cadvisor.yml
└── (Alloy itself lives at /etc/alloy/config.alloy + /etc/default/alloy — host install, not under /opt/GOLD/MON)
```

On each worker VM, under `/opt/GOLD/MON/worker/`:
```
/opt/GOLD/MON/worker/
├── docker-compose.yml
├── config.alloy
└── .env                            (copied from .env.example, one per VM)
```

#   <span style="color:blue;font-weight:bold">3. Fichiers de configuration complets</span>
---

## 3.1 `docker-compose.yml` (Prometheus + Grafana + AlertManager + cAdvisor)
Provided as-is; key points:
- Prometheus runs with `--web.enable-remote-write-receiver` (required for the push architecture) and `--web.enable-lifecycle` (so `update_worker_sd.sh` / rule edits can be picked up with `curl -X POST http://localhost:9090/-/reload` instead of a restart).
- 30-day local retention (`--storage.tsdb.retention.time=30d`) — adjust to your disk budget on SID1.
- AlertManager reaches Postfix on the Docker **host** (not a container) via `extra_hosts: postfix-host:10.240.129.104`, so `alertmanager.yml`'s `smtp_smarthost` can simply say `postfix-host:25`.
- **Replace `GF_SECURITY_ADMIN_PASSWORD=__CHANGE_ME__` before first start.**

## 3.2 `prometheus.yml`
Five scrape jobs: self-monitoring (`prometheus`, `alertmanager`), local containers on SID1 (`cadvisor-sid1`), the 4 known Airflow servers (`alloy-airflow-servers`, `cadvisor-airflow-servers` — static, fixed IPs), and the dynamic workers (`alloy-workers`, `cadvisor-workers` — file-based SD). `env` and `role` labels are attached at the source (in each `.alloy` config's `external_labels`) rather than here, so they arrive correctly on push-based series too.

## 3.3 `prometheus.rules.yml` → `airflow_alerts.rules.yml`
Covers, in order: agent availability (Alloy/cAdvisor unreachable), system-level (CPU/disk/memory), Azure Agent liveness, Airflow (scheduler heartbeat, DAG/task failure spikes, queue depth, no active workers), PostgreSQL (down, replication lag, connections near max), Redis (down, replication broken, memory). Metric names for the Airflow group (`airflow_scheduler_heartbeat_total`, `airflow_dag_run_failed_total`, `airflow_ti_failures_total`, `airflow_executor_queued_tasks`, `celery_workers_online`) follow Airflow 3's OTel metric naming; **validate the exact names against what actually lands in Prometheus after step 4 below** — OTel metric names have changed between Airflow minor versions and this is the single most likely place a first deployment needs adjusting.

## 3.4 `alertmanager.yml`
Routes `severity="critical"` to a wider on-call distribution list with a 1h repeat, everything else to the standard ops list at 6h repeat. An inhibition rule silences downstream Airflow/Postgres/Redis alerts on a host whose agent (`AlloyTargetDown`) is already firing, so a full node outage produces one page, not five.

## 3.5 Postfix configuration
No new service — see `postfix/postfix-relay-notes.md` for the two checks (`inet_interfaces`, `mynetworks`) needed so the existing local Postfix accepts mail from the AlertManager container's Docker network, plus a validation procedure using `amtool`.

## 3.6 Other files provided
- `grafana/provisioning/datasources/prometheus.yml` — auto-provisions the Prometheus datasource on Grafana's first boot.
- `grafana/provisioning/dashboards/dashboards.yml` — provisioning stub; actual dashboards are imported by ID (section 5), not vendored as JSON, so they stay easy to update from grafana.com.
- `alloy/host/airflow-server.alloy` — the Alloy config for SIT1/SIT2/SIP1/SIP2.
- `alloy/host/sid1-supervision.alloy` — the (much smaller) Alloy config for SID1 itself.
- `alloy/host/docker-compose.cadvisor.yml` — the one container still needed on the 4 Airflow servers even though Alloy runs natively there.
- `alloy/worker/config.alloy` + `docker-compose.yml` + `.env.example` — everything needed on a worker VM.

#   <span style="color:blue;font-weight:bold">4. Grafana Alloy — installation et configuration</span>
---

## 4.1 Host install (SID1, SIT1, SIT2, SIP1, SIP2)
Run `scripts/install_alloy_host.sh` as root on each host:
```
# on SIP1
./install_alloy_host.sh SRAI-AIR-SIP1 prod airflow-server.alloy
# on SID1
./install_alloy_host.sh SRAI-AIR-SID1 monitoring sid1-supervision.alloy
```
The script adds Grafana's RPM repo, installs the `alloy` package, deploys the right config to `/etc/alloy/config.alloy` (running it through `dos2unix`, consistent with how every other deployment script in this project handles copied files), writes `MON_HOSTNAME`/`MON_ENV`/`PG_EXPORTER_PASSWORD` into `/etc/default/alloy`, creates the textfile-collector directory, then enables and starts the `alloy` systemd service. If the host runs Postgres (the 4 Airflow servers), it prompts once for the `exporter_user` password and prints the `CREATE USER ... GRANT pg_monitor` statement to run inside the existing `afp-postgres-1` container if that role doesn't exist yet — deliberately a **read-only monitoring role**, separate from `replica_user`.

On the 4 Airflow servers only, also start the small cAdvisor sidecar:
```
docker compose -f cadvisor/docker-compose.cadvisor.yml up -d
```

## 4.2 Docker install (workers)
On each worker VM:
```
cp .env.example .env && vi .env      # set MON_HOSTNAME / MON_ENV for this VM
docker compose up -d
```
This starts both `alloy` (with host `/proc`, `/sys`, `/` bind-mounted read-only so the containerized unix exporter reports **host** metrics, not container metrics) and `cadvisor`.

## 4.3 Enabling Airflow's OTel metrics
Add to `airflow.cfg` (or the equivalent environment variables, `AIRFLOW__METRICS__OTEL_*`) on every Airflow component — apiserver, scheduler, triggerer, dag-processor, and the worker's own `celery worker` process:
```ini
[metrics]
otel_on = True
otel_host = localhost
otel_port = 4317
otel_prefix = airflow
otel_interval_milliseconds = 30000
otel_ssl_active = False
```
`otel_host = localhost` because Alloy's OTLP receiver runs on the **same host** as the Airflow process emitting the metric (the 4 Airflow servers) or the **same container network** as the worker's celery process (see the worker's `docker-compose.yml` port mapping if celery itself also runs in Docker there — adjust `otel_host` to the alloy container's service name in that case rather than `localhost`).

This requires the OTel extra to be present in the custom image:
```dockerfile
RUN pip install 'apache-airflow[otel]' --break-system-packages
```
Add this line to the `airflow-custom:3.2.0` Dockerfile and rebuild before rolling this out — same mechanism already used for other package additions in that image (see `_PIP_ADDITIONAL_REQUIREMENTS` vs Dockerfile note in the platform deployment doc).

## 4.4 Validation
```bash
# 1. Alloy is up and pushing
curl -s http://<node-ip>:12345/metrics | grep alloy_build_info

# 2. Prometheus sees the agent (self-health, pull path)
curl -s 'http://10.240.129.104:9090/api/v1/query?query=up{job=~"alloy-.*"}'

# 3. Business metrics actually arrived (push path) — pick one from each source
curl -s 'http://10.240.129.104:9090/api/v1/query?query=node_load1' | jq .
curl -s 'http://10.240.129.104:9090/api/v1/query?query=pg_up' | jq .
curl -s 'http://10.240.129.104:9090/api/v1/query?query=redis_up' | jq .
curl -s 'http://10.240.129.104:9090/api/v1/query?query={__name__=~"airflow_.*"}' | jq .
```
If the last query returns nothing after `otel_on = True` and an Airflow restart, see Troubleshooting (section 9) — this is the step most likely to need iteration.

#   <span style="color:blue;font-weight:bold">5. Dashboards Grafana</span>
---
Import these by ID (**Dashboards → New → Import**) rather than vendoring JSON, so updates from the community stay easy to pull:

| Dashboard | grafana.com ID | Covers |
|---|---|---|
| Node Exporter Full | 1860 | System metrics (works against Alloy's unix exporter output as-is) |
| PostgreSQL Database | 9628 | postgres_exporter metrics |
| Redis Dashboard for Prometheus Redis Exporter | 763 | redis_exporter metrics |
| Docker Monitoring (cAdvisor) | 893 | Per-container metrics |
| Grafana Alloy | 20714 | Alloy's own health/pipeline metrics |

There is no single well-established community dashboard ID yet for Airflow's native OTel metrics (the integration is recent); build a small custom dashboard once real metric names are confirmed in step 4.4, using panels for: scheduler heartbeat gap, DAG/task failure rate, executor queue depth, and active Celery workers by `env`.

**Data source & variables**: point every imported dashboard at the `Prometheus` datasource provisioned in `grafana/provisioning/datasources/prometheus.yml`. Add two dashboard template variables so stage/prod and per-host drill-down work everywhere:
```
env  -> label_values(up, env)
host -> label_values(up{env="$env"}, host)
```
Every metric in this stack carries both labels (attached via `external_labels` in each `.alloy` config), so this works uniformly across node/Postgres/Redis/Airflow/Celery panels.

#   <span style="color:blue;font-weight:bold">6. Procédure de déploiement pas à pas</span>
---

## 6.1 Prérequis
- Docker + Docker Compose v2 on SID1 and on the worker VMs.
- Firewall: allow `10.240.129.99/.100/.101/.102/.30(+)` → `10.240.129.104:9090` (remote_write) and the reverse `10.240.129.104` → each node's `:12345` (agent health scrape). Open `3000`, `9090`, `9093` on SID1 only to the operations subnet, not broadly.
- Postgres `exporter_user` role (`pg_monitor`) created once per instance (prompted by `install_alloy_host.sh`, section 4.1).
- Custom Airflow image rebuilt with `apache-airflow[otel]` (section 4.3).

## 6.2 Installation sur le serveur de supervision (SID1)
```bash
mkdir -p /opt/GOLD/MON && cd /opt/GOLD/MON
# copy docker-compose.yml, prometheus/, alertmanager/, grafana/, scripts/ here
sed -i 's/__CHANGE_ME__/<a real password>/' docker-compose.yml
docker compose up -d
docker compose ps          # all 4 containers healthy
```
Then apply the Postfix checks from `postfix/postfix-relay-notes.md`, and run `install_alloy_host.sh` for SID1 itself (section 4.1) so the supervision host reports its own system metrics too.

## 6.3 Installation de Grafana Alloy sur les nœuds cibles
- 4 Airflow servers: `install_alloy_host.sh` (host) + `docker-compose.cadvisor.yml` (section 4.1).
- Workers: `docker-compose up -d` in `/opt/GOLD/MON/worker/` (section 4.2).
- Enable Airflow's OTel exporter on every component (section 4.3) and rebuild/redeploy the custom image.

## 6.4 Vérifications de bout en bout
1. Run the four `curl` checks in section 4.4 from SID1.
2. Open Grafana (`http://SRAI-AIR-SID1:3000`, `admin` / the password you set), confirm the Prometheus datasource is green, import the dashboards from section 5, set `env`/`host` variables and confirm both stage and prod hosts appear.
3. Trigger one test alert end-to-end: temporarily stop a worker's `alloy` container, confirm `AlloyTargetDown` fires within ~3 minutes and an email lands via the Postfix test in `postfix-relay-notes.md`, then restart it and confirm the resolved notification arrives.
4. Add the currently-known worker to `scripts/worker_inventory.csv` and run `update_worker_sd.sh`; confirm the new target shows up under **Status → Targets** in Prometheus within `refresh_interval` (60s) without any restart.

#   <span style="color:blue;font-weight:bold">7. Stratégie de découverte des workers</span>
---
`scripts/update_worker_sd.sh` reads a small CSV (`hostname,ip,env`) — sourced from whatever inventory you already maintain (Ansible inventory export, CMDB extract, an Azure Resource Graph query, or just a hand-edited list while the fleet is still ~1 VM) — and regenerates `prometheus/file_sd/workers.json` and `workers_cadvisor.json`. Prometheus's `file_sd_configs` picks up the change automatically (`refresh_interval: 60s`, no reload/restart needed), which is exactly what `file_sd` is for.

As covered in sections 1 and 6.4: this discovery path only controls the **agent-health pull scrape** (`up{job="alloy-workers"}`). A worker's actual business metrics arrive by push the moment its Alloy container starts, independent of when file_sd notices it — so there's no gap in real data collection while you're mid-way through onboarding the remaining ~15 workers, only a brief gap (≤60s) in the "is this specific agent alive" signal.

To scale this later without hand-editing CSV rows (e.g. once the workers are provisioned via an Azure ARM/Terraform pipeline with predictable tags), replace the CSV read in `update_worker_sd.sh` with a call to Azure Resource Graph or your CMDB's API — the JSON-writing half of the script doesn't need to change.

#   <span style="color:blue;font-weight:bold">8. SOLUTION_SUMMARY.md</span>
---
Provided as a separate file — see `SOLUTION_SUMMARY.md` alongside this guide for the executive synthesis (architecture diagram, component table, points d'attention, next steps).

#   <span style="color:blue;font-weight:bold">9. Troubleshooting</span>
---

**No `airflow_*` metrics in Prometheus after enabling `otel_on`.**
Check, in order: (1) Airflow process logs for an OTel exporter connection error at startup; (2) whether the issue is gRPC vs HTTP — Airflow's OTel exporter defaults to gRPC on the configured `otel_port`, so if `otel_port = 4317` still yields nothing, try pointing it at `4318` and confirm Alloy's HTTP receiver logs an incoming connection (`docker logs mon-alloy` or `journalctl -u alloy -f`); (3) that the custom image actually has `apache-airflow[otel]` installed (`pip show opentelemetry-exporter-otlp` inside the container) and wasn't skipped because `_PIP_ADDITIONAL_REQUIREMENTS` was set instead of rebuilding via the Dockerfile — this project has hit that exact gap before (see the platform deployment doc's note on `docker-compose.yaml` `build: .`).

**`up{job="alloy-workers"}` never appears for a new worker.**
Confirm `update_worker_sd.sh` actually wrote the new IP into `workers.json` (`cat prometheus/file_sd/workers.json`) and that the file is correctly bind-mounted read-only into the Prometheus container (`docker exec mon-prometheus cat /etc/prometheus/file_sd/workers.json`). If the file is right but Prometheus still doesn't show the target, check **Status → Service Discovery** in the Prometheus UI for a parse error.

**AlertManager doesn't relay mail.**
Work through `postfix/postfix-relay-notes.md` end to end — the two most common misses are `inet_interfaces = loopback-only` (Postfix not listening on the docker0/bridge interface at all) and `mynetworks` not including the compose network's actual subnet (which shifts if the compose project name or network definition changes).

**`pg_up` is 0 / postgres_exporter can't connect.**
Confirm the `exporter_user` role exists and has `pg_monitor` (section 4.1's prompt only creates the password entry in `/etc/default/alloy`, it prints — but does not itself run — the `CREATE USER` statement inside the Postgres container), and that `01-replication.conf`'s `pg_hba.conf` rules (or an equivalent local rule) allow `exporter_user` to connect from `localhost` — the existing replication rule only covers `replica_user` from the `10.240.129.0/24` subnet, a local connection from `localhost` typically falls under a different, already-present `pg_hba.conf` line, but verify rather than assume on a locked-down instance.

**Redis metrics look empty even though `redis_up == 1`.**
`prometheus.exporter.redis` in the worker/server `.alloy` configs points at `localhost:6378` (the port the existing Redis deployment doc documents) — if the exporter reports up but with no keyspace metrics, check the container is the **primary** on that host, since read replicas expose most stats identically but a couple of keyspace fields differ; this is expected, not a defect.
