#!/bin/bash
# Uninstall all core components
set -e

helm uninstall risingwave -n etl || true
helm uninstall loki -n etl || true
helm uninstall pgadmin -n etl || true
helm uninstall grafana -n etl || true
helm uninstall prometheus -n etl || true
helm uninstall redpanda -n etl || true
helm uninstall pg -n etl || true
helm uninstall vault -n etl || true
helm uninstall airflow -n etl || true

# Remove Debezium Kafka Connect deployment and connector ConfigMap
kubectl delete deployment kafka-connect-debezium -n etl || true
kubectl delete configmap debezium-pg-sales-connector-config -n etl || true

# Remove finalizers from all PVCs and pods in etl namespace

# Remove finalizers from all major resource types in etl namespace
for kind in pod pvc replicaset statefulset deployment service; do
  for res in $(kubectl get $kind -n etl -o name); do
    kubectl patch "$res" -n etl -p '{"metadata":{"finalizers":[]}}' --type=merge || true
  done
done

# Optionally delete namespace
# kubectl delete namespace etl

