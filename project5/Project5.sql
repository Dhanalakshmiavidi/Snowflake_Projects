CREATE OR REPLACE WAREHOUSE STAR_WH
WITH WAREHOUSE_SIZE='XSMALL'
AUTO_SUSPEND=300
AUTO_RESUME=TRUE;

CREATE OR REPLACE DATABASE STAR_DB;
CREATE OR REPLACE SCHEMA STAR_DB.SALES_STAR_SCHEMA;

USE WAREHOUSE STAR_WH;
USE DATABASE STAR_DB;
USE SCHEMA SALES_STAR_SCHEMA;

CREATE OR REPLACE FILE FORMAT CSV_FF
TYPE='CSV'
FIELD_DELIMITER=','
SKIP_HEADER=1
FIELD_OPTIONALLY_ENCLOSED_BY='"'
NULL_IF=('NULL','null','');

CREATE OR REPLACE STAGE STAR_STAGE
FILE_FORMAT=CSV_FF;

CREATE OR REPLACE TABLE DIM_CUSTOMER(
customer_id INT PRIMARY KEY,
customer_name varchar(100),
city varchar(100),
state varchar(100),
membership varchar(100)
);

create or replace table DIM_PRODUCT(
product_id int primary key,
product_name varchar(100),
category varchar(100),
brand varchar(100),
price number(10,2)
);

create or replace table DIM_BRANCH(
branch_id int primary key,
branch_name varchar(100),
city varchar(50),
state varchar(50),
region varchar(50),
manager_name varchar(100)
);

CREATE OR REPLACE TABLE DIM_DATE (
    date_id INT PRIMARY KEY,
    date DATE,
    day INT,
    day_name VARCHAR(20),
    week_no INT,
    month VARCHAR(20),
    quarter VARCHAR(10),
    year INT,
    is_weekend VARCHAR(10)
);


CREATE OR REPLACE TABLE FACT_SALES (
    sale_id INT PRIMARY KEY,
    customer_id INT,
    product_id INT,
    branch_id INT,
    date_id INT,
    quantity INT,
    total_amount NUMBER(10, 2),
    FOREIGN KEY (customer_id) REFERENCES DIM_CUSTOMER(customer_id),
    FOREIGN KEY (product_id) REFERENCES DIM_PRODUCT(product_id),
    FOREIGN KEY (branch_id) REFERENCES DIM_BRANCH(branch_id),
    FOREIGN KEY (date_id) REFERENCES DIM_DATE(date_id)
);

COPY INTO DIM_CUSTOMER FROM @STAR_STAGE/customers.csv FILE_FORMAT=(FORMAT_NAME=CSV_FF) FORCE=True;
COPY INTO DIM_PRODUCT FROM @STAR_STAGE/products.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) FORCE = TRUE;
COPY INTO DIM_BRANCH FROM @STAR_STAGE/branches.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) FORCE = TRUE;
COPY INTO DIM_DATE FROM @STAR_STAGE/calendar.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) FORCE = TRUE;
COPY INTO FACT_SALES FROM @STAR_STAGE/sales.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) FORCE = TRUE;


SELECT *FROM DIM_CUSTOMER;
SELECT *FROM DIM_PRODUCT;
SELECT *FROM DIM_BRANCH;
SELECT *FROM DIM_DATE;
SELECT *FROM FACT_SALES;

--customer-wise sales report
select c.customer_id,c.customer_name,
c.membership,sum(f.quantity) as total_units_bought,
sum(f.total_amount) as total_sales
from FACT_SALES f join DIM_CUSTOMER c
on f.customer_id=c.customer_id
group by c.customer_id,c.customer_name,c.membership
order by total_sales desc;


--product-wise revenue report
SELECT p.product_id,p.product_name,p.category,p.brand,
SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS total_revenue
FROM FACT_SALES fJOIN DIM_PRODUCT p ON 
f.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category, p.brand
ORDER BY total_revenue DESC;


--branch-wise revenue report
SELECT b.branch_id,b.branch_name,b.city,b.state,
SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_BRANCH b ON 
f.branch_id = b.branch_id
GROUP BY b.branch_id, b.branch_name, b.city, b.state
ORDER BY total_revenue DESC;

-- state-wise Revenue Report
SELECT b.state,COUNT(DISTINCT b.branch_id) AS total_branches,
SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_BRANCH b ON 
f.branch_id = b.branch_id
GROUP BY b.state
ORDER BY total_revenue DESC;

-- monthly Revenue Report
SELECT d.year,d.month,
SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS monthly_revenue
FROM FACT_SALES f JOIN DIM_DATE d ON 
f.date_id = d.date_id
GROUP BY d.year, d.month
ORDER BY d.year, d.month;

-- quarterly Revenue Report
SELECT d.year,d.quarter,
SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS quarterly_revenue
FROM FACT_SALES f
JOIN DIM_DATE d ON f.date_id = d.date_id
GROUP BY d.year, d.quarter
ORDER BY d.year, d.quarter;

-- top 10 Customers
SELECT c.customer_id,c.customer_name,c.city,c.membership,
SUM(f.total_amount) AS total_spent
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name, c.city, c.membership
ORDER BY total_spent DESC
LIMIT 10;

-- top 10 Products
SELECT p.product_id,p.product_name,p.category,
SUM(f.quantity) AS units_sold,
SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_PRODUCT p ON 
f.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC
LIMIT 10;

-- top 10 Performing Branches
SELECT b.branch_id,b.branch_name,b.city,b.state,
b.manager_name,SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_BRANCH b ON 
f.branch_id = b.branch_id
GROUP BY b.branch_id, b.branch_name, b.city, b.state, b.manager_name
ORDER BY total_revenue DESC
LIMIT 10;

-- category-wise Revenue
SELECT p.category,COUNT(DISTINCT p.product_id) AS total_products,SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS category_revenue
FROM FACT_SALES f JOIN DIM_PRODUCT p ON 
f.product_id = p.product_id
GROUP BY p.category
ORDER BY category_revenue DESC;

--customer purchase trend
select c.membership,count(distinct c.customer_id) as total_customers,count(f.sale_id) as total_transactions,sum(f.quantity) as total_items_purchased,avg(f.total_amount) as avg_transaction,sum(f.total_amount) as total_revenue
from FACT_SALES f JOIN DIM_CUSTOMER c on 
f.customer_id=c.customer_id 
group by c.membership
order by total_revenue desc;


--product performance dashboard
select p.category,p.brand,p.product_name,p.price as unit_price,sum(f.quantity) as total,
sum(f.total_amount) as revenue from
FACT_SALES f JOIN DIM_PRODUCT p on 
f.product_id=p.product_id
group by p.category,p.brand,p.product_name,p.price
order by revenue desc;

--branch Performance Dashboard
SELECT b.region,b.state,b.city,b.branch_name,
b.manager_name,COUNT(DISTINCT f.sale_id) AS total_invoices,SUM(f.quantity) AS items_sold,
SUM(f.total_amount) AS total_branch_revenue
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.branch_id = b.branch_id
GROUP BY b.region, b.state, b.city, b.branch_name, b.manager_name
ORDER BY total_branch_revenue DESC;

-- regional Sales Analysis
SELECT b.region,COUNT(DISTINCT b.branch_id) AS branch_count,SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS regional_revenue
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.branch_id = b.branch_id
GROUP BY b.region
ORDER BY regional_revenue DESC;

-- sales Trend Analysis
SELECT d.date,d.day_name,d.is_weekend,
COUNT(f.sale_id) AS daily_transactions,
SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS daily_revenue
FROM FACT_SALES f
JOIN DIM_DATE d ON f.date_id = d.date_id
GROUP BY d.date, d.day_name, d.is_weekend
ORDER BY d.date;