#!/bin/bash
# Install all core components using Helm
set -e

# Ensure etl namespace exists
kubectl get namespace etl >/dev/null 2>&1 || kubectl create namespace etl

# Create DAGs hostPath PV and PVC for Airflow
echo "Applying DAGs PersistentVolume and PersistentVolumeClaim..."
kubectl apply -f scripts/airflow-dags-pv-pvc.yaml || { echo 'Failed to apply DAGs PV/PVC'; exit 1; }

# Add Helm repos
helm repo add stable https://charts.helm.sh/stable
helm repo add redpanda https://charts.redpanda.com
helm repo add apache-airflow https://airflow.apache.org
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install cert-manager if not present (required for Redpanda)
if ! kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  echo "Installing cert-manager (required for Redpanda)..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
  # Wait for cert-manager pods to be ready
  kubectl wait --for=condition=Available --timeout=180s -n cert-manager deployment/cert-manager-webhook || { echo 'cert-manager not ready'; exit 1; }
else
  echo "cert-manager already installed."
fi


# Install Kubernetes Dashboard if not present
if ! kubectl get ns kubernetes-dashboard >/dev/null 2>&1; then
  echo "Installing Kubernetes Dashboard..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
else
  echo "Kubernetes Dashboard already installed."
fi

# Create dashboard admin ServiceAccount and ClusterRoleBinding if not present
if ! kubectl -n kube-system get sa dashboard-admin-sa >/dev/null 2>&1; then
  echo "Creating dashboard-admin-sa ServiceAccount and ClusterRoleBinding..."
  kubectl -n kube-system create serviceaccount dashboard-admin-sa
  kubectl create clusterrolebinding dashboard-admin-sa --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin-sa
else
  echo "dashboard-admin-sa ServiceAccount and ClusterRoleBinding already exist."
fi

# Print dashboard login token
echo "Dashboard login token:"
kubectl -n kube-system create token dashboard-admin-sa

# Install Airflow (official chart, LocalExecutor with bundled PostgreSQL, using DAGs PVC)
helm upgrade --install airflow apache-airflow/airflow \
  --version 1.16.0 \
  --namespace etl --create-namespace --wait \
  -f scripts/airflow-dags-pvc-values.yaml \
  --set redis.enabled=true \
  --set redis.persistence.enabled=false \
  --set redis.password="" \
  --set airflow.config.celery.broker_url="redis://airflow-redis:6379/0" \
  --set postgresql.primary.persistence.enabled=true \
  --set workers.persistence.enabled=false \
  --set airflow.config.core.dags_folder="/opt/airflow/dags" \
  --set ingress.web.enabled=false \
  --set createUserJob.useHelmHooks=false \
  --set migrateDatabaseJob.useHelmHooks=false \
  --set 'scheduler.extraInitContainers[0].name=fix-volume-logs-permissions' \
  --set 'scheduler.extraInitContainers[0].image=busybox' \
  --set 'scheduler.extraInitContainers[0].command[0]=sh' \
  --set 'scheduler.extraInitContainers[0].command[1]=-c' \
  --set 'scheduler.extraInitContainers[0].command[2]=chown -R 50000:0 /opt/airflow/logs/' \
  --set 'scheduler.extraInitContainers[0].securityContext.runAsUser=0' \
  --set 'scheduler.extraInitContainers[0].volumeMounts[0].mountPath=/opt/airflow/logs/' \
  --set 'scheduler.extraInitContainers[0].volumeMounts[0].name=logs' \
  --set 'workers.extraInitContainers[0].name=fix-volume-logs-permissions' \
  --set 'workers.extraInitContainers[0].image=busybox' \
  --set 'workers.extraInitContainers[0].command[0]=sh' \
  --set 'workers.extraInitContainers[0].command[1]=-c' \
  --set 'workers.extraInitContainers[0].command[2]=chown -R 50000:0 /opt/airflow/logs/' \
  --set 'workers.extraInitContainers[0].securityContext.runAsUser=0' \
  --set 'workers.extraInitContainers[0].volumeMounts[0].mountPath=/opt/airflow/logs/' \
  --set 'workers.extraInitContainers[0].volumeMounts[0].name=logs' \
  --set webserver.nodeSelector."kubernetes\.io/hostname"=k3d-etl-demo-agent-0 \
  --set workers.nodeSelector."kubernetes\.io/hostname"=k3d-etl-demo-agent-0 \
  --set scheduler.nodeSelector."kubernetes\.io/hostname"=k3d-etl-demo-agent-0 \
  --set triggerer.nodeSelector."kubernetes\.io/hostname"=k3d-etl-demo-agent-0

# Install PostgreSQL (stable chart, default settings)
helm upgrade --install pg stable/postgresql --namespace etl --create-namespace --wait



# Install Redpanda (default settings)
helm upgrade --install redpanda redpanda/redpanda --namespace etl --wait

# Install Prometheus
helm upgrade --install prometheus prometheus-community/prometheus --namespace etl --wait

# Install Grafana
helm upgrade --install grafana grafana/grafana --namespace etl --wait \
  --set adminPassword=grafana

# Install Loki
helm upgrade --install loki grafana/loki-stack --namespace etl --wait

# TODO: Add Debezium and RisingWave deployments
