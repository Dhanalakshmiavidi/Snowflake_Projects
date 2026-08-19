

-- Task 1: Create Warehouse
CREATE OR REPLACE WAREHOUSE ENTERPRISE_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- Task 2: Create Database
CREATE OR REPLACE DATABASE ENTERPRISE_DB;

-- Task 3: Create Schema
CREATE OR REPLACE SCHEMA ENTERPRISE_DB.SALES_SCHEMA;

-- Set active context
USE WAREHOUSE ENTERPRISE_WH;
USE DATABASE ENTERPRISE_DB;
USE SCHEMA SALES_SCHEMA;

-- Task 4: Create CSV File Format
CREATE OR REPLACE FILE FORMAT CSV_FILE_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', 'null', '');

-- Task 5: Create Internal Stage
CREATE OR REPLACE STAGE ENTERPRISE_STAGE
    FILE_FORMAT = CSV_FILE_FORMAT;

LIST @ENTERPRISE_STAGE;



CREATE OR REPLACE TABLE CUSTOMERS (
    customer_id INT PRIMARY KEY,
    customer_name VARCHAR(50),
    city VARCHAR(50),
    membership VARCHAR(20)
);

CREATE OR REPLACE TABLE PRODUCTS (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(100),
    category VARCHAR(50),
    price NUMBER(10, 2)
);

CREATE OR REPLACE TABLE BRANCHES (
    branch_id INT PRIMARY KEY,
    branch_name VARCHAR(100),
    state VARCHAR(50)
);

CREATE OR REPLACE TABLE SALES (
    sale_id INT PRIMARY KEY,
    customer_id INT,
    product_id INT,
    branch_id INT,
    quantity INT,
    sale_date DATE,
    total_amount NUMBER(10, 2)
);


CREATE OR REPLACE TABLE SALES_STAGING (
    sale_id INT,
    customer_id INT,
    product_id INT,
    branch_id INT,
    quantity INT,
    sale_date DATE,
    total_amount NUMBER(10, 2)
);



COPY INTO CUSTOMERS FROM @ENTERPRISE_STAGE/customers.csv FILE_FORMAT = (FORMAT_NAME = CSV_FILE_FORMAT) Force=True;
COPY INTO PRODUCTS FROM @ENTERPRISE_STAGE/products.csv FILE_FORMAT = (FORMAT_NAME = CSV_FILE_FORMAT) FORCE=True;
COPY INTO BRANCHES FROM @ENTERPRISE_STAGE/branches.csv FILE_FORMAT = (FORMAT_NAME = CSV_FILE_FORMAT) ON_ERROR = 'CONTINUE';
COPY INTO SALES FROM @ENTERPRISE_STAGE/sales_history.csv FILE_FORMAT = (FORMAT_NAME = CSV_FILE_FORMAT) ON_ERROR = 'CONTINUE';



SELECT * FROM CUSTOMERS;
SELECT * FROM PRODUCTS;
SELECT * FROM BRANCHES;
SELECT * FROM SALES;



--Incremental Loading using Streams and MERGE
CREATE OR REPLACE STREAM SALES_STAGING_STREAM ON TABLE SALES_STAGING;

-- Load new_sales.csv into the Staging Table
COPY INTO SALES_STAGING 
FROM @ENTERPRISE_STAGE/new_sales.csv 
FILE_FORMAT = (FORMAT_NAME = CSV_FILE_FORMAT) 
ON_ERROR = 'CONTINUE'
FORCE = TRUE;


SELECT * FROM SALES_STAGING_STREAM;

--  Merge into the target SALES table
MERGE INTO SALES target
USING SALES_STAGING_STREAM source
ON target.sale_id = source.sale_id
WHEN MATCHED THEN 
    UPDATE SET 
        target.customer_id = source.customer_id,
        target.product_id = source.product_id,
        target.branch_id = source.branch_id,
        target.quantity = source.quantity,
        target.sale_date = source.sale_date,
        target.total_amount = source.total_amount
WHEN NOT MATCHED THEN 
    INSERT (sale_id, customer_id, product_id, branch_id, quantity, sale_date, total_amount)
    VALUES (source.sale_id, source.customer_id, source.product_id, source.branch_id, source.quantity, source.sale_date, source.total_amount);


SELECT * FROM SALES;



-- Data Validation

--  duplicate Sale IDs
SELECT sale_id, COUNT(*) AS count_occurrences
FROM ENTERPRISE_DB.SALES_SCHEMA.SALES
GROUP BY sale_id
HAVING COUNT(*) > 1;

-- Task 15: Identify missing Customer IDs (orphaned sales)
SELECT s.*
FROM SALES s
LEFT JOIN CUSTOMERS c ON s.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- Task 16: Display invalid Product IDs
SELECT s.*
FROM SALES s
LEFT JOIN PRODUCTS p ON s.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Task 17: Count total newly inserted records (sale_id > 5)
SELECT COUNT(*) AS total_newly_inserted_records 
FROM SALES 
WHERE sale_id > 5;

--Time Travel
SET current_query_time = CURRENT_TIMESTAMP();

--  Delete one sales record
DELETE FROM SALES WHERE sale_id = 10;

-- Verify deletion
SELECT * FROM SALES WHERE sale_id = 10;

--  Recover the deleted record using Time Travel (BEFORE query)
INSERT INTO SALES
SELECT * FROM SALES BEFORE (STATEMENT => '01c67757-3203-2b5c-0017-d38e0010fef6')
WHERE sale_id = 10;

SELECT * FROM SALES WHERE sale_id = 10;



-- Create a clone named SALES_TEST
CREATE OR REPLACE TABLE SALES_TEST CLONE SALES;

--Display cloned records
SELECT * FROM SALES_TEST;

--  Insert one new test record into the clone
INSERT INTO SALES_TEST (sale_id, customer_id, product_id, branch_id, quantity, sale_date, total_amount)
VALUES (99, 1, 101, 1, 1, '2026-07-15', 60000);

--  Verify clone has the new record while original SALES remains unchanged
SELECT * FROM SALES_TEST WHERE sale_id = 99;
SELECT * FROM SALES WHERE sale_id = 99; 


--Task Automation

CREATE OR REPLACE TASK INCREMENTAL_SALES_LOAD_TASK
    WAREHOUSE = ENTERPRISE_WH
    SCHEDULE = 'USING CRON 0 0 * * * UTC' -- Runs daily at midnight UTC
    WHEN SYSTEM$STREAM_HAS_DATA('SALES_STAGING_STREAM')
AS
MERGE INTO SALES target
USING SALES_STAGING_STREAM source
ON target.sale_id = source.sale_id
WHEN MATCHED THEN 
    UPDATE SET 
        target.customer_id = source.customer_id,
        target.product_id = source.product_id,
        target.branch_id = source.branch_id,
        target.quantity = source.quantity,
        target.sale_date = source.sale_date,
        target.total_amount = source.total_amount
WHEN NOT MATCHED THEN 
    INSERT (sale_id, customer_id, product_id, branch_id, quantity, sale_date, total_amount)
    VALUES (source.sale_id, source.customer_id, source.product_id, source.branch_id, source.quantity, source.sale_date, source.total_amount);

-- 
ALTER TASK INCREMENTAL_SALES_LOAD_TASK RESUME;

--  Verify Task Status
SHOW TASKS LIKE 'INCREMENTAL_SALES_LOAD_TASK';



--  Customer Revenue Report
SELECT 
    c.customer_id, 
    c.customer_name, 
    SUM(s.total_amount) AS total_revenue
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY total_revenue DESC;

--  Branch Revenue Report
SELECT 
    b.branch_id, 
    b.branch_name, 
    b.state, 
    SUM(s.total_amount) AS total_revenue
FROM BRANCHES b
JOIN SALES s ON b.branch_id = s.branch_id
GROUP BY b.branch_id, b.branch_name, b.state
ORDER BY total_revenue DESC;

-- Product Revenue Report
SELECT 
    p.product_id, 
    p.product_name, 
    p.category, 
    SUM(s.total_amount) AS total_revenue
FROM PRODUCTS p
JOIN SALES s ON p.product_id = s.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC;

--  Monthly Revenue Report
SELECT 
    DATE_TRUNC('MONTH', sale_date) AS sales_month, 
    SUM(total_amount) AS monthly_revenue
FROM SALES
GROUP BY DATE_TRUNC('MONTH', sale_date)
ORDER BY sales_month;

--  Highest Revenue Customer
SELECT 
    c.customer_name, 
    SUM(s.total_amount) AS total_spent
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_name
ORDER BY total_spent DESC
LIMIT 1;

--  Highest Revenue Branch
SELECT 
    b.branch_name, 
    SUM(s.total_amount) AS total_revenue
FROM BRANCHES b
JOIN SALES s ON b.branch_id = s.branch_id
GROUP BY b.branch_name
ORDER BY total_revenue DESC
LIMIT 1;


SELECT 
    p.product_name, 
    SUM(s.total_amount) AS total_revenue
FROM PRODUCTS p
JOIN SALES s ON p.product_id = s.product_id
GROUP BY p.product_name
ORDER BY total_revenue DESC
LIMIT 5;


SELECT 
    c.customer_name, 
    COUNT(s.sale_id) AS total_purchases
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_name
ORDER BY total_purchases DESC;


SELECT 
    sale_id,
    sale_date,
    total_amount,
    SUM(total_amount) OVER (ORDER BY sale_date, sale_id) AS running_revenue
FROM SALES;


SELECT 
    c.customer_name,
    SUM(s.total_amount) AS total_spent,
    DENSE_RANK() OVER (ORDER BY SUM(s.total_amount) DESC) AS customer_rank
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_name;


CREATE OR REPLACE VIEW CUSTOMER_REVENUE AS
SELECT 
    c.customer_id,
    c.customer_name,
    SUM(s.total_amount) AS total_revenue
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_id, c.customer_name;


CREATE OR REPLACE MATERIALIZED VIEW BRANCH_REVENUE AS
SELECT 
    branch_id,
    SUM(total_amount) AS total_revenue
FROM SALES_SCHEMA.SALES
GROUP BY branch_id;


SELECT * FROM CUSTOMER_REVENUE ORDER BY total_revenue DESC;

SELECT 
    b.branch_name, 
    b.state, 
    mv.total_revenue
FROM BRANCH_REVENUE mv
JOIN BRANCHES b ON mv.branch_id = b.branch_id
ORDER BY mv.total_revenue DESC;