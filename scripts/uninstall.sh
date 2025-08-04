#!/bin/bash
# Uninstall all core components
set -e

helm uninstall loki -n etl || true
helm uninstall grafana -n etl || true
helm uninstall prometheus -n etl || true
helm uninstall redpanda -n etl || true
helm uninstall pg -n etl || true
helm uninstall airflow -n etl || true

# Optionally delete namespace
# kubectl delete namespace etl

