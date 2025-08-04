#!/bin/bash
# Port-forward UIs for local access
set -e

echo "Airflow UI: http://localhost:8080"
kubectl port-forward svc/airflow-webserver 8080:8080 -n etl &

echo "Grafana UI: http://localhost:3000"
kubectl port-forward svc/grafana 3000:80 -n etl &

echo "Prometheus UI: http://localhost:9090"
kubectl port-forward svc/prometheus-server 9090:9090 -n etl &

# Add more as needed
wait
