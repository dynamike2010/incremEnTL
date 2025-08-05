#!/bin/bash
# Port-forwarding for local UIs (background)

# Airflow UI: http://localhost:8080/
kubectl port-forward svc/airflow-webserver 8080:8080 -n etl &

# Vault UI/API: http://localhost:8200/
kubectl port-forward svc/vault 8200:8200 -n etl &

# Redpanda Console: http://localhost:8081/
kubectl port-forward svc/redpanda-console 8081:8080 -n etl &

# Grafana: http://localhost:3000/
kubectl port-forward svc/grafana 3000:80 -n etl &

# pgAdmin: http://localhost:5050/
kubectl port-forward svc/pgadmin-pgadmin4 5050:80 -n etl &

# Prometheus: http://localhost:9090/
kubectl port-forward svc/prometheus-server 9090:80 -n etl &

# RisingWave UI: http://localhost:30007
kubectl port-forward svc/risingwave-frontend 30007:4567 -n etl &

# Debezium Kafka Connect API: http://localhost:8083/
kubectl port-forward svc/kafka-connect-debezium 8083:8083 -n etl &

# k8s dashboard: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
kubectl proxy &
