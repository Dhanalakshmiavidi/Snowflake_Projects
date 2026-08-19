
CREATE OR REPLACE WAREHOUSE RETAIL_DW_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

CREATE OR REPLACE DATABASE RETAIL_DW_DB;
CREATE OR REPLACE SCHEMA RETAIL_DW_DB.STAR_SCHEMA;

USE WAREHOUSE RETAIL_DW_WH;
USE DATABASE RETAIL_DW_DB;
USE SCHEMA STAR_SCHEMA;


CREATE OR REPLACE FILE FORMAT CSV_FF
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', 'null', '');

CREATE OR REPLACE STAGE DW_STAGE
    FILE_FORMAT = CSV_FF;




-- Customer Dimension
CREATE OR REPLACE TABLE DIM_CUSTOMER (
    customer_id INT PRIMARY KEY,
    customer_name VARCHAR(50),
    city VARCHAR(50),
    state VARCHAR(50),
    membership VARCHAR(20)
);

-- Product Dimension
CREATE OR REPLACE TABLE DIM_PRODUCT (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(100),
    category VARCHAR(50),
    brand VARCHAR(50),
    price NUMBER(10, 2)
);

-- Branch Dimension
CREATE OR REPLACE TABLE DIM_BRANCH (
    branch_id INT PRIMARY KEY,
    branch_name VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(50)
);

-- Date Dimension
CREATE OR REPLACE TABLE DIM_DATE (
    date_id INT PRIMARY KEY,
    date DATE,
    month VARCHAR(20),
    quarter VARCHAR(10),
    year INT
);

-- Fact Table
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




COPY INTO DIM_CUSTOMER FROM @DW_STAGE/customers.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) ON_ERROR = 'CONTINUE' FORCE = TRUE;
COPY INTO DIM_PRODUCT FROM @DW_STAGE/products.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) ON_ERROR = 'CONTINUE' FORCE = TRUE;
COPY INTO DIM_BRANCH FROM @DW_STAGE/branches.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) ON_ERROR = 'CONTINUE' FORCE = TRUE;
COPY INTO DIM_DATE FROM @DW_STAGE/calendar.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) ON_ERROR = 'CONTINUE' FORCE = TRUE;
COPY INTO FACT_SALES FROM @DW_STAGE/sales.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) ON_ERROR = 'CONTINUE' FORCE = TRUE;



DESCRIBE TABLE FACT_SALES;
DESCRIBE TABLE DIM_CUSTOMER;
DESCRIBE TABLE DIM_PRODUCT;
DESCRIBE TABLE DIM_BRANCH;
DESCRIBE TABLE DIM_DATE;


SELECT * FROM DIM_CUSTOMER;
SELECT * FROM DIM_PRODUCT;
SELECT * FROM DIM_BRANCH;
SELECT * FROM DIM_DATE;
SELECT * FROM FACT_SALES;
--customer-wise Sales Report
SELECT 
    c.customer_id,
    c.customer_name,
    c.membership,
    SUM(f.total_amount) AS total_spent
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name, c.membership
ORDER BY total_spent DESC;

-- Product-wise & Category-wise Revenue Report
SELECT 
    p.product_id,
    p.product_name,
    p.category,
    p.brand,
    SUM(f.quantity) AS total_units_sold,
    SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category, p.brand
ORDER BY total_revenue DESC;

--  Branch & State-wise Sales Report
SELECT 
    b.branch_id,
    b.branch_name,
    b.state,
    SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.branch_id = b.branch_id
GROUP BY b.branch_id, b.branch_name, b.state
ORDER BY total_revenue DESC;

--  Monthly Revenue Report (Time Hierarchy)
SELECT 
    d.year,
    d.quarter,
    d.month,
    SUM(f.total_amount) AS monthly_revenue
FROM FACT_SALES f
JOIN DIM_DATE d ON f.date_id = d.date_id
GROUP BY d.year, d.quarter, d.month
ORDER BY d.year, d.month;


--state-wise Revenue Report
SELECT b.state,COUNT(DISTINCT b.branch_id) AS total_branches,SUM(f.quantity) AS total_quantity,
SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.branch_id = b.branch_id
GROUP BY b.state
ORDER BY total_revenue DESC;

-- category-wise Revenue Report
SELECT p.category,COUNT(DISTINCT p.product_id) AS distinct_products_sold,SUM(f.quantity) AS total_units_sold,SUM(f.total_amount) AS category_revenue
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.product_id = p.product_id
GROUP BY p.category
ORDER BY category_revenue DESC;


SELECT 
    c.customer_name,
    SUM(f.total_amount) AS total_spent
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.customer_id = c.customer_id
GROUP BY c.customer_name
ORDER BY total_spent DESC
LIMIT 1;

-- top 10 Customers 
SELECT c.customer_id,c.customer_name,c.membership,
SUM(f.total_amount) AS total_spent
FROM FACT_SALES f
JOIN DIM_CUSTOMER c ON f.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name, c.membership
ORDER BY total_spent DESC
LIMIT 10;

-- top 10 Products (Sorted by Revenue)
SELECT p.product_id,p.product_name,p.category,
SUM(f.quantity) AS units_sold,
SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f
JOIN DIM_PRODUCT p ON f.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC
LIMIT 10;

-- top Performing Branches
SELECT b.branch_id,b.branch_name,b.city,b.state,
SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f
JOIN DIM_BRANCH b ON f.branch_id = b.branch_id
GROUP BY b.branch_id, b.branch_name, b.city, b.state
ORDER BY total_revenue DESC;

-- sales Trend Analysis
SELECT d.date,d.month,
COUNT(f.sale_id) AS total_transactions,
SUM(f.quantity) AS items_sold,
SUM(f.total_amount) AS daily_revenue
FROM FACT_SALES f
JOIN DIM_DATE d ON f.date_id = d.date_id
GROUP BY d.date, d.month
ORDER BY d.date;