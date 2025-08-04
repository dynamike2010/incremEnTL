from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime
import psycopg2
import os
import logging
import random
import string


# Realistic product and customer name generators
product_adjectives = [
    'Ultra', 'Smart', 'Eco', 'Pro', 'Mini', 'Max', 'Super', 'Power', 'Lite', 'Classic', 'Deluxe', 'Prime', 'Elite', 'Fresh', 'Quick', 'Easy', 'Magic', 'Active', 'Premium', 'Flex'
]
product_nouns = [
    'Phone', 'Laptop', 'Tablet', 'Speaker', 'Camera', 'Watch', 'Book', 'Jacket', 'Sneakers', 'Blender', 'Lamp', 'Backpack', 'Puzzle', 'Cream', 'Bike', 'Drill', 'Guitar', 'Mic', 'Oven', 'Board'
]
first_names = [
    'James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer', 'Michael', 'Linda', 'William', 'Elizabeth', 'David', 'Barbara', 'Richard', 'Susan', 'Joseph', 'Jessica', 'Thomas', 'Sarah', 'Charles', 'Karen',
    'Christopher', 'Nancy', 'Daniel', 'Lisa', 'Matthew', 'Betty', 'Anthony', 'Margaret', 'Mark', 'Sandra', 'Donald', 'Ashley', 'Steven', 'Kimberly', 'Paul', 'Emily', 'Andrew', 'Donna', 'Joshua', 'Michelle'
]
last_names = [
    'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson', 'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin',
    'Lee', 'Perez', 'Thompson', 'White', 'Harris', 'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson', 'Walker', 'Young', 'Allen', 'King', 'Wright', 'Scott', 'Torres', 'Nguyen', 'Hill', 'Flores'
]


def random_product_name():
    return f"{random.choice(product_adjectives)} {random.choice(product_nouns)}"

def random_customer_name():
    return f"{random.choice(first_names)} {random.choice(last_names)}"

def random_street_name():
    return ''.join(random.choices(string.ascii_letters, k=6))

def random_price():
    return round(random.uniform(10, 1000), 2)

def random_zip():
    return ''.join(random.choices(string.digits, k=5))

def random_email(name):
    return f"{name.lower()}@example.com"

def insert_random_data(**kwargs):
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
    product_categories = [
        ('Electronics', ['Smartphones', 'Laptops', 'Tablets', 'Wearables', 'Audio', 'Cameras']),
        ('Books', ['Fiction', 'Non-fiction', 'Comics', 'Children', 'Science', 'History']),
        ('Clothing', ['Men', 'Women', 'Kids', 'Sportswear', 'Accessories', 'Shoes']),
        ('Food', ['Snacks', 'Drinks', 'Groceries', 'Organic', 'Frozen', 'Bakery']),
        ('Home', ['Furniture', 'Decor', 'Kitchen', 'Garden', 'Appliances', 'Lighting']),
        ('Toys', ['Educational', 'Action Figures', 'Puzzles', 'Board Games', 'Outdoor', 'Dolls']),
        ('Beauty', ['Skincare', 'Makeup', 'Haircare', 'Fragrance', 'Men', 'Tools']),
        ('Sports', ['Fitness', 'Outdoor', 'Team Sports', 'Cycling', 'Running', 'Swimming']),
        ('Automotive', ['Car Care', 'Accessories', 'Electronics', 'Tools', 'Tires', 'Motorcycle']),
        ('Music', ['Instruments', 'Accessories', 'Sheet Music', 'Recording', 'DJ', 'Live Sound'])
    ]
    us_states_cities = [
        ('NY', ['New York', 'Buffalo', 'Rochester', 'Albany', 'Syracuse']),
        ('CA', ['Los Angeles', 'San Francisco', 'San Diego', 'Sacramento', 'San Jose']),
        ('TX', ['Houston', 'Dallas', 'Austin', 'San Antonio', 'Fort Worth']),
        ('FL', ['Miami', 'Orlando', 'Tampa', 'Jacksonville', 'Tallahassee']),
        ('IL', ['Chicago', 'Springfield', 'Naperville', 'Peoria', 'Rockford']),
        ('PA', ['Philadelphia', 'Pittsburgh', 'Allentown', 'Erie', 'Scranton']),
        ('OH', ['Columbus', 'Cleveland', 'Cincinnati', 'Toledo', 'Akron']),
        ('GA', ['Atlanta', 'Savannah', 'Augusta', 'Athens', 'Macon']),
        ('NC', ['Charlotte', 'Raleigh', 'Greensboro', 'Durham', 'Winston-Salem']),
        ('WA', ['Seattle', 'Spokane', 'Tacoma', 'Vancouver', 'Bellevue'])
    ]
    try:
        with conn.cursor() as cur:
            # Insert products
            for _ in range(200):
                cat, subcats = random.choice(product_categories)
                name = random_product_name()
                category = cat
                subcategory = random.choice(subcats)
                unit_price = random_price()
                cur.execute(
                    "INSERT INTO products (name, category, subcategory, unit_price) VALUES (%s, %s, %s, %s)",
                    (name, category, subcategory, unit_price)
                )
            # Insert customers
            for _ in range(200):
                name = random_customer_name()
                email = random_email(name.replace(' ', '.'))
                state, cities = random.choice(us_states_cities)
                city = random.choice(cities)
                zip_code = random_zip()
                street = f"{random.randint(1,9999)} {random_street_name()} St"
                cur.execute(
                    "INSERT INTO customers (name, email, zip, state, city, street) VALUES (%s, %s, %s, %s, %s, %s)",
                    (name, email, zip_code, state, city, street)
                )
        conn.commit()
        logging.info('Random products and customers inserted')
    finally:
        conn.close()

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2023, 1, 1),
}

dag = DAG(
    'generate_products_customers',
    default_args=default_args,
    schedule=None,
    catchup=False,
    description='Generate random products and customers in etl DB',
)

insert_data = PythonOperator(
    task_id='insert_random_products_customers',
    python_callable=insert_random_data,
    dag=dag,
)
