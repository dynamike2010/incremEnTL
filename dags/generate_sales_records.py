from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import psycopg2
import os
import logging
import random
import time

def insert_random_sales(**kwargs):
    host = os.environ.get('POSTGRES_HOST', 'pg-postgresql.etl.svc.cluster.local')
    port = int(os.environ.get('POSTGRES_PORT', 5432))
    user = os.environ.get('POSTGRES_USER', 'postgres')
    password = os.environ.get('POSTGRES_PASSWORD', 'postgres')
    dbname = 'etl'
    conn = psycopg2.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        dbname=dbname,
        connect_timeout=5
    )
    try:
        with conn.cursor() as cur:
            # Get all product IDs and their base prices
            cur.execute("SELECT id, unit_price FROM products")
            products = cur.fetchall()  # list of (id, unit_price)
            cur.execute("SELECT id FROM customers")
            customer_ids = [row[0] for row in cur.fetchall()]
            if not products or not customer_ids:
                logging.warning('No products or customers found!')
                return
            for _ in range(60):  # 60 seconds
                n = random.randint(1, 10)
                for _ in range(n):
                    product_id, base_price = random.choice(products)
                    customer_id = random.choice(customer_ids)
                    qty = random.randint(1, 10)
                    # Sale price: base price +/- 20%
                    base_price_f = float(base_price)
                    delta = base_price_f * random.uniform(-0.2, 0.2)
                    sale_price = round(base_price_f + delta, 2)
                    sale_date = datetime.now()
                    cur.execute(
                        "INSERT INTO sales (product_id, customer_id, qty, sale_price, sale_date) VALUES (%s, %s, %s, %s, %s)",
                        (product_id, customer_id, qty, sale_price, sale_date)
                    )
                conn.commit()
                logging.info(f'Inserted {n} sales records')
                time.sleep(1)
    finally:
        conn.close()

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2023, 1, 1),
}

dag = DAG(
    'generate_sales_records',
    default_args=default_args,
    schedule_interval='* * * * *',  # every minute
    catchup=False,
    description='Generate random sales records for random products and customers',
)

insert_sales = PythonOperator(
    task_id='insert_random_sales',
    python_callable=insert_random_sales,
    dag=dag,
)
