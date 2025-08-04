# testing

from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import psycopg2
import os

def ping_postgres(**kwargs):
    # These values should match your Helm chart or k8s service
    host = os.environ.get('POSTGRES_HOST', 'airflow-postgresql.etl.svc.cluster.local')
    port = int(os.environ.get('POSTGRES_PORT', 5432))
    user = os.environ.get('POSTGRES_USER', 'postgres')
    password = os.environ.get('POSTGRES_PASSWORD', 'postgres')
    dbname = os.environ.get('POSTGRES_DB', 'postgres')
    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            dbname=dbname,
            connect_timeout=5
        )
        conn.close()
        import logging
        logging.info('PostgreSQL connection: OK')
    except Exception as e:
        logging.error(f'PostgreSQL connection: ERROR - {e}')
        raise

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2023, 1, 1),
}

dag = DAG(
    'diagnostic_postgres_ping',
    default_args=default_args,
    schedule=None,
    catchup=False,
    description='Diagnostic DAG to ping PostgreSQL pod from Airflow',
)

ping_task = PythonOperator(
    task_id='ping_postgres',
    python_callable=ping_postgres,
    dag=dag,
)
