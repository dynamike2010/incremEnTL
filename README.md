# incremEnTL ETL Demo Stack

This project contains a reproducible ETL stack for local Kubernetes (Minikube) demos, including:
- PostgreSQL (OLTP source)
- Debezium (CDC)
- Redpanda (Kafka broker)
- RisingWave (streaming/batch SQL)
- Airflow (DAG orchestrator)
- dbt-risingwave (transforms)
- Prometheus, Grafana, Loki (observability)
- Optional sinks (Postgres/external)

## Structure
- `charts/` - Helm charts (custom or downloaded)
- `manifests/` - Custom Kubernetes manifests
- `scripts/` - Shell scripts for install/uninstall/port-forward
- `dags/` - Airflow DAGs
- `dbt/` - dbt project for RisingWave


## Quickstart & Node Requirements


**Node Requirements:**
- You must have a Kubernetes cluster with at least 3 agent nodes (for Redpanda to work reliably in multi-broker mode). One server (control-plane) node is required for cluster management. The `--servers 1` flag creates a single control-plane node, which is typical for local dev/test clusters. The `--agents 3` flag ensures three worker nodes for Redpanda.
- For local dev, use k3d or Minikube. Example for k3d:
  ```sh
  k3d cluster create etl-demo --servers 1 --agents 3 --volume $(pwd)/dags:/Users/michalbialek/PycharmProjects/incremEnTL/dags@agent:0,1,2
  # Check cluster status
  k3d cluster list
  ```
## Expected Healthy State (No RisingWave/Debezium Yet)

When the stack is running 100% OK, you should see:

- **Nodes:**
  - 1 control-plane (server) node, 3 agent nodes, all Ready

- **Pods in `etl` namespace:**
  - Airflow: webserver, scheduler, worker, triggerer, redis, postgresql, statsd
  - PostgreSQL: `pg-postgresql-0`
  - Redpanda: 3 brokers (`redpanda-0`, `redpanda-1`, `redpanda-2`), console
  - Prometheus: server, alertmanager, node-exporters, pushgateway, kube-state-metrics
  - Grafana, Loki (and promtail agents)

- **Pods in other namespaces:**
  - `cert-manager` (3 pods)
  - `kubernetes-dashboard` (dashboard + metrics scraper)
  - `kube-system` (coredns, traefik, metrics-server, local-path-provisioner, etc.)

- **Services in `etl`:**
  - Airflow webserver (8080), Redpanda console (8081), Grafana (3000/80), Prometheus (9090/80), PostgreSQL (5432), etc.

- **PVCs/PVs:**
  - All required PVCs and PVs are Bound (see `kubectl get pvc -n etl` and `kubectl get pv`)

- **All pods should be in `Running` or `Completed` state, no CrashLoopBackOff or Error.**

If you see this state, your stack is healthy and ready for use (except for RisingWave/Debezium, which are not yet included).

1. Start k3d (with DAGs hostPath mount and 3+ nodes)
2. (If using Redpanda) Install cert-manager before running the install script:
   ```sh
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
   # Wait for cert-manager pods to be ready
   kubectl -n cert-manager get pods
   ```
3. Run install script:
   ```sh
   ./scripts/install.sh
   ```
4. Access UIs (see port-forward scripts)

## Redpanda and cert-manager
Redpanda Helm chart requires cert-manager for managing TLS certificates. If cert-manager is not installed, Redpanda install will fail with errors about missing Certificate and Issuer CRDs. See Quickstart above for install instructions.

## Diagnosing and Building Context (for LLMs and Humans)

When working with this project (especially for automated agents or new contributors), start by diagnosing the environment and building context:

1. **Check Kubernetes Context and Cluster:**
   - `kubectl config current-context`
   - `kubectl get nodes -o wide`
   - `kubectl get ns`
   - `kubectl get pods -A`

2. **Check Airflow and Database Connectivity:**
   - Inspect Airflow DAGs in `dags/` (e.g., `diag.py` for Postgres connectivity test)
   - Check environment variables for service hostnames and credentials

3. **Review Project Structure:**
   - See the `Structure` section above for folder purposes

4. **Review Helm and K8s Manifests:**
   - Helm chart sources: `charts/helm-sources.yaml`
   - Custom manifests: `manifests/`
   - Install scripts: `scripts/install.sh`

5. **Check for Running Services:**
   - Use `kubectl get pods -n etl` and other relevant namespaces

6. **For LLMs:**
   - Always start by running the diagnostic kubectl commands above to understand the current environment before making assumptions or changes.

## Utility Scripts

- `scripts/pf.sh`: Port-forwards key services (Airflow, Redpanda Console, Grafana, Prometheus) from the `etl` namespace to localhost for easy UI access. Run this script after installation to access UIs in your browser.
  - Airflow: http://localhost:8080/
  - Redpanda Console: http://localhost:8081/
  - Grafana: http://localhost:3000/
  - Prometheus: http://localhost:9090/

- `scripts/uninstall.sh`: Uninstalls all core Helm releases (Airflow, PostgreSQL, Redpanda, Prometheus, Grafana, Loki) from the `etl` namespace. Optionally, you can uncomment the last line to delete the entire namespace and all resources within it.

## Helpful Commands

### Cluster & Node Management
- `k3d cluster list` — List all k3d clusters
- `k3d cluster stop etl-demo` — Stop the cluster
- `k3d cluster start etl-demo` — Start the cluster

### Dashboard & Access
- `kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml` — Install Kubernetes Dashboard
- `kubectl create serviceaccount dashboard-admin-sa -n kube-system` — Create admin SA
- `kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin-sa` — Bind admin role
- `kubectl -n kube-system create token dashboard-admin-sa` — Get login token
- `kubectl proxy &` — Start proxy for dashboard access

**Note:** If you get a 401 error after entering a valid dashboard token, open the dashboard in a new browser tab/window. This is due to CSRF token issues in some browsers.

### Airflow (inside pod or container)
- `airflow db migrate` — Migrate Airflow DB
- `airflow users list` — List Airflow users
- `airflow users create --username airflow --password airflow --role Admin --email airflow@airflow.com --firstname Air --lastname Flow` — Create admin user

### Helm & K8s Troubleshooting
- `helm uninstall airflow -n etl` — Uninstall Airflow
- `kubectl delete pod --all -n etl --grace-period=0 --force` — Force delete all pods in etl
- `./scripts/uninstall.sh` — Uninstall all core components
- `kubectl get all -n etl; kubectl get pvc -n etl; kubectl get pv` — List all resources, PVCs, PVs
- `kubectl delete pvc --all -n etl; kubectl delete pv airflow-dags-pv; kubectl get pvc -n etl; kubectl get pv` — Clean up storage

### Port-forwarding & Process Management
- `kubectl port-forward svc/airflow-webserver 8080:8080 -n etl &`
- `kubectl port-forward svc/redpanda-console 8081:8080 -n etl &`
- `kubectl port-forward svc/grafana 3000:80 -n etl &`
- `kubectl port-forward svc/prometheus-server 9090:80 -n etl &`
- `kubectl proxy &`
- `ps aux | grep 'kubectl port-forward' | grep -v grep` — Find port-forward processes
- `ps aux | grep 'kubectl proxy' | grep -v grep` — Find proxy processes

### General K8s
- `kubectl get pods --all-namespaces`
- `kubectl get pods -n etl`

## TODO
- Add install scripts and instructions
- Add sample DAGs and dbt models
- Add custom manifests as needed
