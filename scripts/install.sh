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
helm repo add runix https://helm.runix.net/
helm repo add risingwavelabs https://risingwavelabs.github.io/helm-charts/ --force-update
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


# Print dashboard login token (permanent, does not expire)
echo "Dashboard login token (permanent, does not expire):"
kubectl -n kube-system get secret dashboard-admin-sa-token -o jsonpath='{.data.token}' | base64 --decode; echo


# Create a permanent dashboard token (Secret) for demo use
if ! kubectl -n kube-system get secret dashboard-admin-sa-token >/dev/null 2>&1; then
  echo "Creating permanent dashboard token (Secret) from file..."
  kubectl -n kube-system apply -f scripts/dashboard-admin-sa-token.yaml
  # Wait for token to be populated
  sleep 2
else
  echo "Permanent dashboard token Secret already exists."
fi

echo "Dashboard login token (permanent, does not expire):"
kubectl -n kube-system get secret dashboard-admin-sa-token -o jsonpath='{.data.token}' | base64 --decode; echo

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

# Install PostgreSQL (stable chart, custom password)
helm upgrade --install pg stable/postgresql --namespace etl --create-namespace --wait \
  --set postgresqlPassword=postgres



# Install Redpanda (standard Helm install)
helm upgrade --install redpanda redpanda/redpanda --namespace etl --wait

# Deploy Debezium connector ConfigMap and Kafka Connect (Debezium) after Redpanda is running
echo "Applying Debezium connector ConfigMap..."
kubectl apply -f scripts/debezium-pg-sales-connector-configmap.yaml
echo "Deploying Kafka Connect with Debezium..."
kubectl apply -f manifests/kafka-connect-debezium.yaml
echo "Debezium CDC for sales table is now enabled via Kafka Connect."

# Install Prometheus
helm upgrade --install prometheus prometheus-community/prometheus --namespace etl --wait

# Install Grafana
helm upgrade --install grafana grafana/grafana --namespace etl --wait \
  --set adminPassword=grafana

# Install Loki
helm upgrade --install loki grafana/loki-stack --namespace etl --wait

# Reset pgAdmin state to ensure servers.json is loaded on first start
kubectl delete pod -n etl -l app.kubernetes.io/name=pgadmin4 --ignore-not-found
kubectl delete pvc -n etl -l app.kubernetes.io/name=pgadmin4 --ignore-not-found
kubectl apply -f scripts/pgadmin-servers-configmap.yaml
helm upgrade --install pgadmin runix/pgadmin4 --namespace etl --create-namespace --wait \
  --set service.type=ClusterIP \
  --set env.email=airflow@airflow.com \
  --set env.password=airflow \
  --set persistence.enabled=false \
  --set 'extraVolumeMounts[0].name=pgadmin-servers' \
  --set 'extraVolumeMounts[0].mountPath=/pgadmin4/servers.json' \
  --set 'extraVolumeMounts[0].subPath=servers.json' \
  --set 'extraVolumes[0].name=pgadmin-servers' \
  --set 'extraVolumes[0].configMap.name=pgadmin-servers' \
  --set env.PGADMIN_CONFIG_SERVER_MODE=False

# TODO: Add Debezium and RisingWave deployments

# Install RisingWave (standalone for demo, can be customized)
helm upgrade --install risingwave risingwavelabs/risingwave \
  --namespace etl --create-namespace --wait \
  --version 0.2.33 \
  -f scripts/risingwave-values.yaml

