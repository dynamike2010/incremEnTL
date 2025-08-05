#!/bin/bash
# Register Debezium connector with Kafka Connect via REST API
set -e

# Wait for Kafka Connect REST API to be available
PORT=8083
SVC=kafka-connect-debezium
NAMESPACE=etl

# Get current Postgres password from K8s secret, trim trailing percent or newline
PG_PASS=$(kubectl get secret pg-postgresql -n $NAMESPACE -o json | jq -r '.data["postgres-password"]' | base64 --decode | tr -d '\n' | sed 's/%$//')

# Update connector JSON with current password (in-place, backup to .bak)
cp scripts/debezium-pg-sales-connector.json scripts/debezium-pg-sales-connector.json.bak
jq --arg pass "$PG_PASS" '.config["database.password"] = $pass' scripts/debezium-pg-sales-connector.json.bak > scripts/debezium-pg-sales-connector.json

for i in {1..30}; do
  if curl -s http://localhost:$PORT/ &>/dev/null; then break; fi
  if [ $i -eq 1 ]; then kubectl port-forward svc/$SVC $PORT:$PORT -n $NAMESPACE & PF_PID=$!; fi
  sleep 2
done
sleep 3
echo "Registering Debezium connector via REST API..."
curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" --data @scripts/debezium-pg-sales-connector.json http://localhost:$PORT/connectors | grep -qE '200|201' && \
  echo "Debezium connector registered successfully." || echo "Debezium connector registration may have failed (check logs)."
if [ -n "$PF_PID" ]; then kill $PF_PID; fi
