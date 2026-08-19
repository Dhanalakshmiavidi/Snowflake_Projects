
CREATE OR REPLACE WAREHOUSE SALES_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE or REPLACE DATABASE CUSTOMER_SALES_DB;

CREATE OR REPLACE SCHEMA CUSTOMER_SALES_DB.SALES_SCHEMA;

USE WAREHOUSE SALES_WH;
USE DATABASE CUSTOMER_SALES_DB;
USE SCHEMA SALES_SCHEMA;

CREATE OR REPLACE FILE FORMAT CSV_FILE_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', 'null', '');

    CREATE OR REPLACE STAGE SALES_STAGE
    FILE_FORMAT = CSV_FILE_FORMAT;


    SHOW WAREHOUSES;
    SHOW DATABASES;
    SHOW SCHEMAS;
    SHOW FILE FORMATS;
    SHOW STAGES;

    LIST @SALES_STAGE;


    CREATE OR REPLACE TABLE CUSTOMERS (
    customer_id INT PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    phone VARCHAR(20),
    address VARCHAR(100)
);

CREATE OR REPLACE TABLE FOODITEMS (
    food_id INT PRIMARY KEY,
    name VARCHAR(100),
    price NUMBER(10, 2),
    category VARCHAR(50),
    availability VARCHAR(20)
);

CREATE OR REPLACE TABLE ORDERS (
    order_id INT PRIMARY KEY,
    customer_id INT,
    food_id INT,
    quantity INT,
    order_date TIMESTAMP_NTZ,
    status VARCHAR(30),
    total_amount NUMBER(10, 2),
    FOREIGN KEY (customer_id) REFERENCES CUSTOMERS(customer_id),
    FOREIGN KEY (food_id) REFERENCES FOODITEMS(food_id)
);

COPY INTO CUSTOMERS
FROM @SALES_STAGE/customers.csv
FILE_FORMAT = (FORMAT_NAME = CSV_FILE_FORMAT)
ON_ERROR = 'CONTINUE';

COPY INTO FOODITEMS
FROM @SALES_STAGE/fooditems.csv
FILE_FORMAT = (FORMAT_NAME = CSV_FILE_FORMAT)
ON_ERROR = 'CONTINUE';

COPY INTO ORDERS
FROM @SALES_STAGE/orders.csv
FILE_FORMAT = (FORMAT_NAME = CSV_FILE_FORMAT)
ON_ERROR = 'CONTINUE';

SELECT * FROM CUSTOMERS;
SELECT * FROM FOODITEMS;
SELECT * FROM ORDERS;

SELECT c.customer_id as Customer_ID,concat(c.first_name,' ',c.last_name) as CustomerName,sum(o.total_amount) as TotalSpent
from CUSTOMERS c join ORDERS o on c.customer_id=o.customer_id
group by c.customer_id,c.first_name,c.last_name
order by customer_id;



SELECT c.customer_id as Customer_ID,concat(c.first_name,' ',c.last_name) as CustomerName,sum(o.total_amount) as TotalSpent
from CUSTOMERS c join ORDERS o on c.customer_id=o.customer_id
group by c.customer_id,c.first_name,c.last_name
order by TotalSpent desc limit 1;


select sum(total_amount) as TotalRevenue
from ORDERS;


SELECT f.category as Category,sum(o.total_amount) as Revenue
from FOODITEMS f join ORDERS o 
on f.food_id=o.food_id
group by f.category
order by Revenue desc;



select status,sum(total_amount) as Revenue
from ORDERS
group by status
order by Revenue desc;

SELECT c.customer_id as Customer_ID,concat(c.first_name,' ',c.last_name) as CustomerName,sum(o.total_amount) as TotalSpent
from CUSTOMERS c join ORDERS o on c.customer_id=o.customer_id
group by c.customer_id,c.first_name,c.last_name
order by TotalSpent desc limit 3;


SELECT c.customer_id as Customer_ID,concat(c.first_name,' ',c.last_name) as CustomerName,count(o.order_id) as OrderPlaced
from CUSTOMERS c join ORDERS o on c.customer_id=o.customer_id
group by c.customer_id,c.first_name,c.last_name
order by OrderPlaced desc;



select order_id,customer_id,food_id,status,total_amount from ORDERS 
where status='Delivered';

select o.order_id,concat(c.first_name,' ',c.last_name) as CustomerName,o.order_date,o.status,o.total_amount from ORDERS o join CUSTOMERS c on o.customer_id=c.customer_id
where DATE(o.order_date)>'2026-07-12'
order by order_date asc;

CREATE OR REPLACE VIEW CUSTOMER_SALES_REPORT AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    SUM(o.total_amount) AS total_amount_spent
FROM customers c
JOIN orders o
ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name;

SELECT * FROM CUSTOMER_SALES_REPORT;