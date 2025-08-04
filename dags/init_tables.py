from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import psycopg2
import os
import logging

SQL_PATH = os.path.join(os.path.dirname(__file__), 'init_tables.sql')

def run_sql_script(**kwargs):
    host = os.environ.get('POSTGRES_HOST', 'pg-postgresql.etl.svc.cluster.local')
    port = int(os.environ.get('POSTGRES_PORT', 5432))
    user = os.environ.get('POSTGRES_USER', 'postgres')
    password = os.environ.get('POSTGRES_PASSWORD', 'postgres')
    etl_db = 'etl'
    
    # Step 1: Connect to 'postgres' and create 'etl' DB if needed
    conn = psycopg2.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        dbname='postgres',
        connect_timeout=5
    )
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute(f"CREATE DATABASE {etl_db} WITH OWNER = '{user}' ENCODING = 'UTF8' TEMPLATE template1" )
    except psycopg2.errors.DuplicateDatabase:
        logging.info('Database etl already exists')
    finally:
        conn.close()
    
    # Step 2: Connect to 'etl' DB and run schema
    with open(SQL_PATH, 'r') as f:
        sql = f.read()
    conn2 = psycopg2.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        dbname=etl_db,
        connect_timeout=5
    )
    try:
        with conn2.cursor() as cur:
            cur.execute(sql)
        conn2.commit()
        logging.info('SQL script executed successfully in etl DB')
    finally:
        conn2.close()

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2023, 1, 1),
}

dag = DAG(
    'init_tables',
    default_args=default_args,
    schedule=None,
    catchup=False,
    description='Create required tables in PostgreSQL using init_tables.sql',
)

run_sql = PythonOperator(
    task_id='run_init_tables_sql',
    python_callable=run_sql_script,
    dag=dag,
)
