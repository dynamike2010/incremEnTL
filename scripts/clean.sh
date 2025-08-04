#!/bin/bash
# Clean up all Airflow and PostgreSQL PVCs and PVs in the etl namespace
set -e

echo "Deleting all Airflow and PostgreSQL pods in etl namespace..."
kubectl delete pod -n etl -l app.kubernetes.io/name=airflow --ignore-not-found
kubectl delete pod -n etl -l app.kubernetes.io/name=postgresql --ignore-not-found

echo "Deleting all PVCs in etl namespace..."
kubectl delete pvc -n etl --all --ignore-not-found

echo "Deleting all PVs..."
kubectl delete pv --all --ignore-not-found

echo "Cleanup complete."


# kubectl delete pvc --all -n etl
# kubectl delete pv --all
# kubectl delete secret --all -n etl
# kubectl delete configmap --all -n etl
# kubectl delete deployment --all -n etl
# kubectl delete statefulset --all -n etl
# kubectl delete job --all -n etl
# kubectl delete pod --all -n etl
