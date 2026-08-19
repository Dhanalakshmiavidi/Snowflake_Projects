CREATE OR REPLACE WAREHOUSE RETAIL_WH
WITH WAREHOUSE_SIZE='XSMALL'
AUTO_SUSPEND=300
AUTO_RESUME=TRUE
INITIALLY_SUSPENDED=TRUE;

CREATE OR REPLACE DATABASE RETAIL_DB;

CREATE OR REPLACE SCHEMA RETAIL_DB.SALES_SCHEMA;

USE WAREHOUSE RETAIL_WH;
USE DATABASE RETAIL_DB;
USE SCHEMA SALES_SCHEMA;

CREATE OR REPLACE FILE FORMAT RETAIL_CSV_FORMAT TYPE='CSV'
FIELD_DELIMITER=','
SKIP_HEADER=1
FIELD_OPTIONALLY_ENCLOSED_BY='"'
NULL_IF=('NULL','null','');

CREATE OR REPLACE STAGE RETAIL_STAGE
FILE_FORMAT=RETAIL_CSV_FORMAT;

CREATE OR REPLACE TABLE CUSTOMERS(customer_id int primary key,
customer_name varchar(50),
city varchar(50),membership varchar(20));

create or replace table PRODUCTS(product_id int primary key,
product_name varchar(100),category varchar(50),price number(10,2));

create or replace table BRANCHE(branch_id int primary key,
branch_name varchar(100),city varchar(50));

create or replace table SALES(sale_id int primary key,customer_id int,product_id int,
branch_id int,quantity int,sale_date date,total_amount number(10,2),
foreign key (customer_id) references CUSTOMERS(customer_id),
foreign key (product_id) references PRODUCTS(product_id),
foreign key (branch_id) references BRANCHE(branch_id));

COPY INTO CUSTOMERS FROM @RETAIL_STAGE/customers.csv FILE_FORMAT=(FORMAT_NAME=RETAIL_CSV_FORMAT) ON_ERROR='CONTINUE';
COPY INTO PRODUCTS FROM @RETAIL_STAGE/products.csv FILE_FORMAT=(FORMAT_NAME=RETAIL_CSV_FORMAT) ON_ERROR='CONTINUE';
COPY INTO BRANCHE FROM @RETAIL_STAGE/branches.csv FILE_FORMAT=(FORMAT_NAME=RETAIL_CSV_FORMAT) ON_ERROR='CONTINUE';
COPY INTO SALES FROM @RETAIL_STAGE/sales.csv FILE_FORMAT=(FORMAT_NAME=RETAIL_CSV_FORMAT) ON_ERROR='CONTINUE';

select *from CUSTOMERS;
SELECT *FROM PRODUCTS;
SELECT *FROM BRANCHE;
SELECT *FROM SALES;

--total business revenue
SELECT SUM(total_amount) as total_business_revenue from SALES;

--customer-wise sales
SELECT c.customer_id,c.customer_name,sum(s.total_amount) as total_spent
from CUSTOMERS C JOIN SALES s on c.customer_id=s.customer_id
group by c.customer_id,c.customer_name
order by c.customer_id;

--branch-wise sales
select b.branch_id,b.branch_name,sum(s.total_amount) as total_sales
from BRANCHE b join SALES s on b.branch_id=s.branch_id
group by b.branch_id,b.branch_name
order by total_sales;


--product-wise sales
SELECT 
    p.product_id, 
    p.product_name, 
    SUM(s.total_amount) AS total_revenue
FROM PRODUCTS p
JOIN SALES s ON p.product_id = s.product_id
GROUP BY p.product_id, p.product_name
ORDER BY total_revenue DESC;


--category-wise sales
SELECT 
    p.category, 
    SUM(s.total_amount) AS total_revenue
FROM PRODUCTS p
JOIN SALES s ON p.product_id = s.product_id
GROUP BY p.category
ORDER BY total_revenue DESC;


--highest revenue branch
SELECT 
    b.branch_name, 
    SUM(s.total_amount) AS total_sales
FROM BRANCHE b
JOIN SALES s ON b.branch_id = s.branch_id
GROUP BY b.branch_name
ORDER BY total_sales DESC
LIMIT 1;


--highest spending customer
select c.customer_name,sum(s.total_amount) as total_spent
from CUSTOMERS c join SALES s on c.customer_id=s.customer_id
group by c.customer_name
order by total_spent desc 
limit 1;


--top3 products
SELECT 
    p.product_name, 
    SUM(s.total_amount) AS total_revenue
FROM PRODUCTS p
JOIN SALES s ON p.product_id = s.product_id
GROUP BY p.product_name
ORDER BY total_revenue DESC
LIMIT 3;


--top three customers
SELECT 
    c.customer_name, 
    SUM(s.total_amount) AS total_spent
FROM CUSTOMERS c
JOIN SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_name
ORDER BY total_spent DESC
LIMIT 3;

--window functions
select c.customer_name,sum(s.total_amount) as total_spent,
dense_rank() over(order by sum(total_amount) desc) as customer_rank
from CUSTOMERS c join SALES s on c.customer_id=s.customer_id
group by c.customer_name;

select b.branch_name,sum(s.total_amount) as total_sales,
dense_rank() over (order by total_sales desc) as branch_rank
from BRANCHE b join SALES s on b.branch_id=s.branch_id
group by branch_name;


select sale_id,sale_date,total_amount,sum(total_amount) over(order by sale_date,sale_id) as cumulative_sales
from SALES;

select sale_id,customer_id,total_amount,avg(total_amount) over() as global_avg_sale_amount
from SALES;


--cte

with CustomerRevenue as (
    select 
        c.customer_id,
        c.customer_name,
        SUM(s.total_amount) as total_spent
    from CUSTOMERS c
    join SALES s on c.customer_id = s.customer_id
    group by c.customer_id, c.customer_name
)
select * from CustomerRevenue;


with CustomerRevenue as (
    select 
        c.customer_id,
        c.customer_name,
        sum(s.total_amount) as total_spent
    from CUSTOMERS c
    join SALES s on c.customer_id = s.customer_id
    group by c.customer_id, c.customer_name
)
select customer_name, total_spent
from CustomerRevenue
where total_spent > (select AVG(total_spent) from CustomerRevenue);



--views
create or replace view SALES_REPORT as  select s.sale_id,s.sale_date,
c.customer_name,p.product_name,p.category,b.branch_name,s.quantity,s.total_amount
from SALES s join CUSTOMERS c on s.customer_id=c.customer_id
join PRODUCTS p on s.product_id=p.product_id
join BRANCHE b on s.branch_id=b.branch_id;

CREATE OR REPLACE VIEW TOP_CUSTOMERS AS
SELECT 
    c.customer_id,
    c.customer_name,
    SUM(s.total_amount) AS total_spent
FROM SALES_SCHEMA.CUSTOMERS c 
JOIN SALES_SCHEMA.SALES s ON c.customer_id = s.customer_id
GROUP BY c.customer_id, c.customer_name;


SELECT *FROM SALES_REPORT;
SELECT *FROM TOP_CUSTOMERS;