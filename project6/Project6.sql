CREATE OR REPLACE WAREHOUSE SNOWFLAKE_SCHEMA_WH
WITH WAREHOUSE_SIZE='XSMALL'
AUTO_SUSPEND=300
AUTO_RESUME=TRUE;

CREATE OR REPLACE DATABASE RETAIL_SNOWFLAKE_DB;
CREATE OR REPLACE SCHEMA RETAIL_SNOWFLAKE_DB.NORMALIZED_SCHEMA;

USE WAREHOUSE SNOWFLAKE_SCHEMA_WH;
USE DATABASE RETAIL_SNOWFLAKE_DB;
USE SCHEMA NORMALIZED_SCHEMA;

CREATE OR REPLACE FILE FORMAT CSV_FF
TYPE='CSV'
FIELD_DELIMITER=',' SKIP_HEADER=1
FIELD_OPTIONALLY_ENCLOSED_BY='"'
NULL_IF=('NULL','null','');

CREATE OR REPLACE STAGE STG_STAGE FILE_FORMAT=CSV_FF;


--staging tables to receive raw csv

CREATE OR REPLACE TABLE STG_CUSTOMER(customer_id INT,customer_name varchar(100),city varchar(50),state varchar(50),membership varchar(50));

CREATE OR REPLACE TABLE STG_PRODUCT(product_id int,product_name varchar(100),category varchar(100),brand varchar(100),price number(10,2));

CREATE OR REPLACE TABLE STG_BRANCHES (branch_id INT, branch_name VARCHAR(100), city VARCHAR(50), state VARCHAR(50), region VARCHAR(50), manager_name VARCHAR(100));

CREATE OR REPLACE TABLE STG_CALENDAR(date_id int, date DATE, day int, day_name varchar(20), week_no int, month varchar(20), quarter varchar(10), year int, is_weekend varchar(10));

CREATE OR REPLACE TABLE STG_SALES(sale_id int, customer_id int, product_id int, branch_id int, date_id int, quantity int, total_amount number(10, 2));

COPY INTO STG_CUSTOMER FROM @STG_STAGE/customers.csv FILE_FORMAT=(FORMAT_NAME=CSV_FF)FORCE=TRUE;
COPY INTO STG_PRODUCT FROM @STG_STAGE/products.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) FORCE = TRUE;
COPY INTO STG_BRANCHES FROM @STG_STAGE/branches.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) FORCE = TRUE;
COPY INTO STG_CALENDAR FROM @STG_STAGE/calendar.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) FORCE = TRUE;
COPY INTO STG_SALES FROM @STG_STAGE/sales.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF) FORCE = TRUE;

SELECT *FROM STG_CUSTOMER;
SELECT *FROM STG_PRODUCT;
SELECT *FROM STG_BRANCHES;
SELECT *FROM STG_CALENDAR;
SELECT *FROM STG_SALES;


--normalized 

CREATE OR REPLACE TABLE DIM_REGION (region_id INT AUTOINCREMENT PRIMARY KEY,region_name VARCHAR(50) UNIQUE);

CREATE OR REPLACE TABLE DIM_STATE (state_id INT AUTOINCREMENT PRIMARY KEY,region_id INT,state_name VARCHAR(50) UNIQUE,FOREIGN KEY (region_id) REFERENCES DIM_REGION(region_id));

CREATE OR REPLACE TABLE DIM_CITY (city_id INT AUTOINCREMENT PRIMARY KEY,state_id INT,city_name VARCHAR(50),
FOREIGN KEY (state_id) REFERENCES DIM_STATE(state_id));

-- Product Hierarchy Tables
CREATE OR REPLACE TABLE DIM_CATEGORY (category_id INT AUTOINCREMENT PRIMARY KEY,category_name VARCHAR(50) UNIQUE);

CREATE OR REPLACE TABLE DIM_BRAND (brand_id INT AUTOINCREMENT PRIMARY KEY,category_id INT,brand_name VARCHAR(50),
FOREIGN KEY (category_id) REFERENCES DIM_CATEGORY(category_id));

-- Time Hierarchy Tables
CREATE OR REPLACE TABLE DIM_YEAR (year_id INT AUTOINCREMENT PRIMARY KEY,year_number INT UNIQUE);

CREATE OR REPLACE TABLE DIM_QUARTER (quarter_id INT AUTOINCREMENT PRIMARY KEY,year_id INT,quarter_name VARCHAR(10),
FOREIGN KEY (year_id) REFERENCES DIM_YEAR(year_id));

CREATE OR REPLACE TABLE DIM_MONTH (month_id INT AUTOINCREMENT PRIMARY KEY,quarter_id INT,month_name VARCHAR(20),FOREIGN KEY (quarter_id) REFERENCES DIM_QUARTER(quarter_id));

-- Base Dimension Tables
CREATE OR REPLACE TABLE DIM_CUSTOMER (customer_id INT PRIMARY KEY,customer_name VARCHAR(100),city_id INT,membership VARCHAR(20),
FOREIGN KEY (city_id) REFERENCES DIM_CITY(city_id));

CREATE OR REPLACE TABLE DIM_PRODUCT (product_id INT PRIMARY KEY,product_name VARCHAR(100),brand_id INT,price NUMBER(10, 2),
FOREIGN KEY (brand_id) REFERENCES DIM_BRAND(brand_id));

CREATE OR REPLACE TABLE DIM_BRANCH (branch_id INT PRIMARY KEY,branch_name VARCHAR(100),city_id INT,manager_name VARCHAR(100),
FOREIGN KEY (city_id) REFERENCES DIM_CITY(city_id));

CREATE OR REPLACE TABLE DIM_DATE (date_id INT PRIMARY KEY,date DATE,month_id INT,day INT,day_name VARCHAR(20),week_no INT,is_weekend VARCHAR(10),
FOREIGN KEY (month_id) REFERENCES DIM_MONTH(month_id));

-- Fact Table
CREATE OR REPLACE TABLE FACT_SALES (sale_id INT PRIMARY KEY,customer_id INT,product_id INT,branch_id INT,date_id INT,quantity INT,total_amount NUMBER(10, 2),
    FOREIGN KEY (customer_id) REFERENCES DIM_CUSTOMER(customer_id),
    FOREIGN KEY (product_id) REFERENCES DIM_PRODUCT(product_id),
    FOREIGN KEY (branch_id) REFERENCES DIM_BRANCH(branch_id),
    FOREIGN KEY (date_id) REFERENCES DIM_DATE(date_id));


SELECT *FROM DIM_REGION;
SELECT *FROM DIM_STATE;
SELECT *FROM DIM_CITY;
SELECT *FROM DIM_CATEGORY;
SELECT *FROM DIM_BRAND;
SELECT *FROM DIM_YEAR;
SELECT *FROM DIM_QUARTER;
SELECT *FROM DIM_MONTH;
SELECT *FROM DIM_CUSTOMER;
SELECT *FROM DIM_PRODUCT;
SELECT *FROM DIM_BRANCH;
SELECT *FROM DIM_DATE;
SELECT *FROM FACT_SALES;

-- ETL TRANSFORMATION

INSERT INTO DIM_REGION (region_name)
SELECT DISTINCT COALESCE(region, 'Other') FROM STG_BRANCHES;

INSERT INTO DIM_STATE (state_name, region_id)
SELECT DISTINCT b.state, r.region_id
FROM STG_BRANCHES b JOIN DIM_REGION r ON COALESCE(b.region, 'Other') = r.region_name
UNION
SELECT DISTINCT c.state, 1FROM STG_CUSTOMER c
WHERE c.state NOT IN (SELECT state FROM STG_BRANCHES);

INSERT INTO DIM_CITY (city_name, state_id)
SELECT DISTINCT b.city, s.state_id FROM STG_BRANCHES b JOIN DIM_STATE s ON b.state = s.state_name
UNION
SELECT DISTINCT c.city, s.state_id FROM STG_CUSTOMER c JOIN DIM_STATE s ON c.state = s.state_name
WHERE c.city NOT IN (SELECT city FROM STG_BRANCHES);


INSERT INTO DIM_CATEGORY (category_name)
SELECT DISTINCT category FROM STG_PRODUCT;

INSERT INTO DIM_BRAND (brand_name, category_id)
SELECT DISTINCT p.brand, c.category_id FROM STG_PRODUCT p
JOIN DIM_CATEGORY c ON p.category = c.category_name;


INSERT INTO DIM_YEAR (year_number)
SELECT DISTINCT year FROM STG_CALENDAR;

INSERT INTO DIM_QUARTER (quarter_name, year_id)
SELECT DISTINCT cal.quarter, y.year_id FROM STG_CALENDAR cal JOIN DIM_YEAR y ON cal.year = y.year_number;

INSERT INTO DIM_MONTH (month_name, quarter_id)
SELECT DISTINCT cal.month, q.quarter_id FROM STG_CALENDAR cal JOIN DIM_YEAR y ON cal.year = y.year_number
JOIN DIM_QUARTER q ON cal.quarter = q.quarter_name AND q.year_id = y.year_id;


INSERT INTO DIM_CUSTOMER (customer_id, customer_name, city_id, membership) 
SELECT c.customer_id, c.customer_name, ct.city_id, c.membership FROM STG_CUSTOMER c JOIN DIM_CITY ct ON c.city = ct.city_name;

INSERT INTO DIM_PRODUCT (product_id, product_name, brand_id, price)
SELECT p.product_id, p.product_name, b.brand_id, p.price FROM STG_PRODUCT p JOIN DIM_BRAND b ON p.brand = b.brand_name;

INSERT INTO DIM_BRANCH (branch_id, branch_name, city_id, manager_name)
SELECT br.branch_id, br.branch_name, ct.city_id, br.manager_name FROM STG_BRANCHES br JOIN DIM_CITY ct ON br.city = ct.city_name;

INSERT INTO DIM_DATE (date_id, date, month_id, day, day_name, week_no, is_weekend)
SELECT cal.date_id, cal.date, m.month_id, cal.day, cal.day_name, cal.week_no, cal.is_weekend FROM STG_CALENDAR cal
JOIN DIM_YEAR y ON cal.year = y.year_number JOIN DIM_QUARTER q ON cal.quarter = q.quarter_name AND q.year_id = y.year_id
JOIN DIM_MONTH m ON cal.month = m.month_name AND m.quarter_id = q.quarter_id;


INSERT INTO FACT_SALES (sale_id, customer_id, product_id, branch_id, date_id, quantity, total_amount)
SELECT sale_id, customer_id, product_id, branch_id, date_id, quantity, total_amount
FROM STG_SALES;

SELECT *FROM FACT_SALES;

-- VALIDATION 

SELECT COUNT(*) AS unmatched_customers  FROM FACT_SALES f LEFT JOIN DIM_CUSTOMER c ON f.customer_id = c.customer_id 
WHERE c.customer_id IS NULL;

SELECT COUNT(*) AS unmatched_products FROM FACT_SALES f LEFT JOIN DIM_PRODUCT p ON f.product_id = p.product_id 
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS unmatched_branches FROM FACT_SALES f LEFT JOIN DIM_BRANCH b ON f.branch_id = b.branch_id 
WHERE b.branch_id IS NULL;

SELECT COUNT(*) AS unmatched_dates FROM FACT_SALES f LEFT JOIN DIM_DATE d ON f.date_id = d.date_id 
WHERE d.date_id IS NULL;

-- Overall validation
SELECT 
    COUNT(*) AS total_sales_records,
    COUNT(DISTINCT customer_id) AS distinct_customers,
    COUNT(DISTINCT product_id) AS distinct_products,
    COUNT(DISTINCT branch_id) AS distinct_branches,
    COUNT(DISTINCT date_id) AS distinct_dates
FROM FACT_SALES;

-- Hierarchical Product Revenue (Category -> Brand -> Product)
SELECT cat.category_name,b.brand_name,p.product_name,SUM(f.quantity) AS total_units_sold,SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_PRODUCT p ON f.product_id = p.product_id JOIN DIM_BRAND b ON p.brand_id = b.brand_id
JOIN DIM_CATEGORY cat ON b.category_id = cat.category_id
GROUP BY cat.category_name, b.brand_name, p.product_name
ORDER BY total_revenue DESC;

-- Hierarchical Regional Sales (Region -> State -> City -> Branch)
SELECT r.region_name,s.state_name,ct.city_name,br.branch_name,
SUM(f.total_amount) AS total_revenue FROM FACT_SALES f
JOIN DIM_BRANCH br ON f.branch_id = br.branch_id
JOIN DIM_CITY ct ON br.city_id = ct.city_id
JOIN DIM_STATE s ON ct.state_id = s.state_id
JOIN DIM_REGION r ON s.region_id = r.region_id
GROUP BY r.region_name, s.state_name, ct.city_name, br.branch_name
ORDER BY total_revenue DESC;

-- Hierarchical Time Analysis (Year -> Quarter -> Month)
SELECT y.year_number,q.quarter_name,m.month_name,SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_DATE d ON f.date_id = d.date_id JOIN DIM_MONTH m ON d.month_id = m.month_id
JOIN DIM_QUARTER q ON m.quarter_id = q.quarter_id JOIN DIM_YEAR y ON q.year_id = y.year_id
GROUP BY y.year_number, q.quarter_name, m.month_name
ORDER BY y.year_number, q.quarter_name;


-- 1. Customer-wise Sales Report
SELECT c.customer_id,c.customer_name,c.membership,ct.city_name,s.state_name,SUM(f.quantity) AS total_units_bought,
SUM(f.total_amount) AS total_sales FROM FACT_SALES f JOIN DIM_CUSTOMER c ON f.customer_id = c.customer_id
JOIN DIM_CITY ct ON c.city_id = ct.city_id JOIN DIM_STATE s ON ct.state_id = s.state_id
GROUP BY c.customer_id, c.customer_name, c.membership, ct.city_name, s.state_name
ORDER BY total_sales DESC;

-- 2. Product-wise Revenue Report
SELECT p.product_id,p.product_name,b.brand_name,cat.category_name,SUM(f.quantity) AS total_units_sold,SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_PRODUCT p ON f.product_id = p.product_id JOIN DIM_BRAND b ON p.brand_id = b.brand_id
JOIN DIM_CATEGORY cat ON b.category_id = cat.category_id GROUP BY p.product_id, p.product_name, b.brand_name, cat.category_name
ORDER BY total_revenue DESC;

-- 3. Brand-wise Revenue Report
SELECT b.brand_id,b.brand_name,cat.category_name,COUNT(DISTINCT p.product_id) AS total_products,SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS total_revenue FROM FACT_SALES f JOIN DIM_PRODUCT p ON f.product_id = p.product_id
JOIN DIM_BRAND b ON p.brand_id = b.brand_id JOIN DIM_CATEGORY cat ON b.category_id = cat.category_id
GROUP BY b.brand_id, b.brand_name, cat.category_name
ORDER BY total_revenue DESC;

-- 4. Category-wise Revenue Report
SELECT cat.category_id,cat.category_name,COUNT(DISTINCT b.brand_id) AS total_brands,COUNT(DISTINCT p.product_id) AS total_products,
SUM(f.quantity) AS total_units_sold,SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_PRODUCT p ON f.product_id = p.product_id JOIN DIM_BRAND b ON p.brand_id = b.brand_id
JOIN DIM_CATEGORY cat ON b.category_id = cat.category_id GROUP BY cat.category_id, cat.category_name
ORDER BY total_revenue DESC;

-- 5. City-wise Sales Report
SELECT ct.city_id,ct.city_name,s.state_name,r.region_name,COUNT(DISTINCT f.sale_id) AS total_orders,SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS total_revenue FROM FACT_SALES f JOIN DIM_BRANCH br ON f.branch_id = br.branch_id
JOIN DIM_CITY ct ON br.city_id = ct.city_id JOIN DIM_STATE s ON ct.state_id = s.state_id
JOIN DIM_REGION r ON s.region_id = r.region_id GROUP BY ct.city_id, ct.city_name, s.state_name, r.region_name
ORDER BY total_revenue DESC;

-- 6. State-wise Revenue Report
SELECT s.state_id,s.state_name,r.region_name,COUNT(DISTINCT br.branch_id) AS total_branches,SUM(f.quantity) AS total_units_sold,SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_BRANCH br ON f.branch_id = br.branch_id JOIN DIM_CITY ct ON br.city_id = ct.city_id
JOIN DIM_STATE s ON ct.state_id = s.state_id JOIN DIM_REGION r ON s.region_id = r.region_id
GROUP BY s.state_id, s.state_name, r.region_name
ORDER BY total_revenue DESC;

-- 7. Region-wise Revenue Report
SELECT r.region_id,r.region_name,COUNT(DISTINCT s.state_id) AS states_covered,COUNT(DISTINCT br.branch_id) AS branches_operating,SUM(f.quantity) AS total_units_sold,
SUM(f.total_amount) AS total_revenue FROM FACT_SALES f JOIN DIM_BRANCH br ON f.branch_id = br.branch_id
JOIN DIM_CITY ct ON br.city_id = ct.city_id JOIN DIM_STATE s ON ct.state_id = s.state_id JOIN DIM_REGION r ON s.region_id = r.region_id
GROUP BY r.region_id, r.region_name
ORDER BY total_revenue DESC;

-- 8. Monthly Revenue Report
SELECT y.year_number,q.quarter_name,m.month_id,m.month_name,SUM(f.quantity) AS total_units_sold,SUM(f.total_amount) AS monthly_revenue
FROM FACT_SALES f JOIN DIM_DATE d ON f.date_id = d.date_id JOIN DIM_MONTH m ON d.month_id = m.month_id
JOIN DIM_QUARTER q ON m.quarter_id = q.quarter_id JOIN DIM_YEAR y ON q.year_id = y.year_id
GROUP BY y.year_number, q.quarter_name, m.month_id, m.month_name
ORDER BY y.year_number, m.month_id;

-- 9. Quarterly Revenue Report
SELECT y.year_number,q.quarter_id,q.quarter_name,SUM(f.quantity) AS total_units_sold,SUM(f.total_amount) AS quarterly_revenue
FROM FACT_SALES f JOIN DIM_DATE d ON f.date_id = d.date_id JOIN DIM_MONTH m ON d.month_id = m.month_id
JOIN DIM_QUARTER q ON m.quarter_id = q.quarter_id JOIN DIM_YEAR y ON q.year_id = y.year_id
GROUP BY y.year_number, q.quarter_id, q.quarter_name
ORDER BY y.year_number, q.quarter_id;

-- 10. Top 10 Customers
SELECT c.customer_id,c.customer_name,c.membership,ct.city_name,SUM(f.total_amount) AS total_spent
FROM FACT_SALES f JOIN DIM_CUSTOMER c ON f.customer_id = c.customer_id JOIN DIM_CITY ct ON c.city_id = ct.city_id
GROUP BY c.customer_id, c.customer_name, c.membership, ct.city_name
ORDER BY total_spent DESC
LIMIT 10;

-- 11. Top 10 Products
SELECT p.product_id,p.product_name,b.brand_name,cat.category_name,SUM(f.quantity) AS units_sold,
SUM(f.total_amount) AS total_revenue FROM FACT_SALES f JOIN DIM_PRODUCT p ON f.product_id = p.product_id JOIN DIM_BRAND b ON p.brand_id = b.brand_id
JOIN DIM_CATEGORY cat ON b.category_id = cat.category_id GROUP BY p.product_id, p.product_name, b.brand_name, cat.category_name
ORDER BY total_revenue DESC
LIMIT 10;

-- 12. Top 10 Branches
SELECT br.branch_id,br.branch_name,ct.city_name,s.state_name,r.region_name,br.manager_name,SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_BRANCH br ON f.branch_id = br.branch_id JOIN DIM_CITY ct ON br.city_id = ct.city_id
JOIN DIM_STATE s ON ct.state_id = s.state_id JOIN DIM_REGION r ON s.region_id = r.region_id
GROUP BY br.branch_id, br.branch_name, ct.city_name, s.state_name, r.region_name, br.manager_name
ORDER BY total_revenue DESC
LIMIT 10;

-- 13. Customer Purchase Trend
SELECT c.membership,m.month_name,COUNT(DISTINCT c.customer_id) AS customer_count,COUNT(f.sale_id) AS total_purchases,SUM(f.quantity) AS total_units_bought,
AVG(f.total_amount) AS avg_order_value,SUM(f.total_amount) AS total_revenue FROM FACT_SALES f JOIN DIM_CUSTOMER c 
ON f.customer_id = c.customer_id JOIN DIM_DATE d ON f.date_id = d.date_id JOIN DIM_MONTH m ON d.month_id = m.month_id
GROUP BY c.membership, m.month_name
ORDER BY total_revenue DESC;

-- 14. Product Performance Dashboard
SELECT cat.category_name,b.brand_name,p.product_name,p.price,COUNT(f.sale_id) AS total_orders,SUM(f.quantity) AS volume_sold,
SUM(f.total_amount) AS gross_sales FROM FACT_SALES f JOIN DIM_PRODUCT p ON f.product_id = p.product_id
JOIN DIM_BRAND b ON p.brand_id = b.brand_id JOIN DIM_CATEGORY cat ON b.category_id = cat.category_id
GROUP BY cat.category_name, b.brand_name, p.product_name, p.price
ORDER BY gross_sales DESC;

-- 15. Regional Sales Dashboard
SELECT r.region_name,s.state_name,ct.city_name,br.branch_name,br.manager_name,COUNT(DISTINCT c.customer_id) AS distinct_customers,
COUNT(f.sale_id) AS total_orders,SUM(f.quantity) AS total_quantity_sold,SUM(f.total_amount) AS total_revenue
FROM FACT_SALES f JOIN DIM_BRANCH br ON f.branch_id = br.branch_id JOIN DIM_CUSTOMER c ON f.customer_id = c.customer_id
JOIN DIM_CITY ct ON br.city_id = ct.city_id JOIN DIM_STATE s ON ct.state_id = s.state_id JOIN DIM_REGION r ON s.region_id = r.region_id
GROUP BY r.region_name, s.state_name, ct.city_name, br.branch_name, br.manager_name
ORDER BY r.region_name, total_revenue DESC;