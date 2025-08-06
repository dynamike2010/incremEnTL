#!/bin/bash
# Install all core components using Helm, using per-service values.yaml files
set -e

# Ensure etl namespace exists
kubectl get namespace etl >/dev/null 2>&1 || kubectl create namespace etl

# Add Helm repos
helm repo add stable https://charts.helm.sh/stable
helm repo add redpanda https://charts.redpanda.com
helm repo add apache-airflow https://airflow.apache.org
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add runix https://helm.runix.net/
helm repo add risingwavelabs https://risingwavelabs.github.io/helm-charts/ --force-update
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install cert-manager if not present (required for Redpanda)
if ! kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
  kubectl wait --for=condition=Available --timeout=180s -n cert-manager deployment/cert-manager-webhook || { echo 'cert-manager not ready'; exit 1; }
fi

# Create DAGs hostPath PV and PVC for Airflow (must exist before Airflow install)
kubectl apply -f scripts/airflow-dags-pv-pvc.yaml || { echo 'Failed to apply DAGs PV/PVC'; exit 1; }

# Install Airflow (using airflow-values.yaml)
helm upgrade --install airflow apache-airflow/airflow \
  --namespace etl --create-namespace --wait \
  -f values/airflow-values.yaml

# Always delete the PostgreSQL PVC and pod to ensure password is set to 'postgres' and data directory is clean
for pvc in $(kubectl get pvc -n etl -l app.kubernetes.io/instance=pg,app.kubernetes.io/name=postgresql -o name); do
  kubectl patch "$pvc" -n etl -p '{"metadata":{"finalizers":[]}}' --type=merge || true
done
kubectl delete pvc -n etl -l app.kubernetes.io/instance=pg,app.kubernetes.io/name=postgresql --ignore-not-found
kubectl wait --for=delete pvc -n etl -l app.kubernetes.io/instance=pg,app.kubernetes.io/name=postgresql --timeout=60s || echo "Postgres PVC already deleted or not found."
kubectl delete pod -n etl -l app.kubernetes.io/instance=pg,app.kubernetes.io/name=postgresql --ignore-not-found
kubectl wait --for=delete pod -n etl -l app.kubernetes.io/instance=pg,app.kubernetes.io/name=postgresql --timeout=60s || echo "Postgres pod already deleted or not found."

# Install PostgreSQL (using postgres-values.yaml)
helm upgrade --install pg bitnami/postgresql \
  --namespace etl --create-namespace --wait \
  -f values/postgres-values.yaml

# Install Redpanda (using redpanda-values.yaml)
helm upgrade --install redpanda redpanda/redpanda --namespace etl --wait \
  # No values file used (was empty)

echo "Creating Debezium topic dbserver1.public.sales in Redpanda (if not exists)..."
kubectl exec -n etl redpanda-0 -c redpanda -- rpk topic create dbserver1.public.sales --partitions 1 --replicas 3 || true

# Deploy Debezium connector ConfigMap and Kafka Connect (Debezium)
kubectl apply -f scripts/debezium-pg-sales-connector-configmap.yaml
kubectl apply -f manifests/kafka-connect-debezium.yaml

# Install Prometheus (using prometheus-values.yaml)
helm upgrade --install prometheus prometheus-community/prometheus --namespace etl --wait \
  # No values file used (was empty)

# Install Grafana (using grafana-values.yaml)
helm upgrade --install grafana grafana/grafana --namespace etl --wait \
  -f values/grafana-values.yaml

# Install Vault (using vault-values.yaml)
helm upgrade --install vault hashicorp/vault --namespace etl --create-namespace --wait \
  -f values/vault-values.yaml

# Install Loki (using loki-values.yaml)
helm upgrade --install loki grafana/loki-stack --namespace etl --wait \
  # No values file used (was empty)

# Reset pgAdmin state to ensure servers.json is loaded on first start
kubectl delete pod -n etl -l app.kubernetes.io/name=pgadmin4 --ignore-not-found
kubectl wait --for=delete pod -n etl -l app.kubernetes.io/name=pgadmin4 --timeout=60s || echo "pgAdmin pod already deleted or not found."
kubectl delete pvc -n etl -l app.kubernetes.io/name=pgadmin4 --ignore-not-found
kubectl wait --for=delete pvc -n etl -l app.kubernetes.io/name=pgadmin4 --timeout=60s || echo "pgAdmin PVC already deleted or not found."
kubectl apply -f scripts/pgadmin-servers-configmap.yaml
helm upgrade --install pgadmin runix/pgadmin4 --namespace etl --create-namespace --wait \
  -f values/pgadmin-values.yaml

# Install RisingWave (using risingwave-values.yaml)
helm upgrade --install risingwave risingwavelabs/risingwave \
  --namespace etl --create-namespace --wait \
  -f values/risingwave-values.yaml

scripts/register-debezium-connector.sh
