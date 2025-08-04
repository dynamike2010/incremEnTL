from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import psycopg2
import os
import logging
import random

def generate_million_sales(**kwargs):
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
        connect_timeout=10
    )
    try:
        with conn.cursor() as cur:
            # Clear all sales records
            cur.execute("TRUNCATE TABLE sales")
            conn.commit()
            logging.info('All sales records cleared')
            # Get all product IDs and their base prices
            cur.execute("SELECT id, unit_price FROM products")
            products = cur.fetchall()
            cur.execute("SELECT id FROM customers")
            customer_ids = [row[0] for row in cur.fetchall()]
            if not products or not customer_ids:
                logging.warning('No products or customers found!')
                return
            batch = []
            for i in range(1_000_000):
                product_id, base_price = random.choice(products)
                customer_id = random.choice(customer_ids)
                qty = random.randint(1, 10)
                base_price_f = float(base_price)
                delta = base_price_f * random.uniform(-0.2, 0.2)
                sale_price = round(base_price_f + delta, 2)
                sale_date = datetime.now()
                batch.append((product_id, customer_id, qty, sale_price, sale_date))
                if len(batch) == 1000:
                    cur.executemany(
                        "INSERT INTO sales (product_id, customer_id, qty, sale_price, sale_date) VALUES (%s, %s, %s, %s, %s)",
                        batch
                    )
                    conn.commit()
                    logging.info(f'Inserted {i+1} sales records so far')
                    batch = []
            # Insert any remaining
            if batch:
                cur.executemany(
                    "INSERT INTO sales (product_id, customer_id, qty, sale_price, sale_date) VALUES (%s, %s, %s, %s, %s)",
                    batch
                )
                conn.commit()
                logging.info(f'Inserted final {len(batch)} sales records')
    finally:
        conn.close()

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2023, 1, 1),
}

dag = DAG(
    'generate_sales_records',
    default_args=default_args,
    schedule=None,
    catchup=False,
    description='Clear sales and generate 1 million random sales records',
)

gen_sales = PythonOperator(
    task_id='generate_million_sales',
    python_callable=generate_million_sales,
    dag=dag,
)

