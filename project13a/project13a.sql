use warehouse COMPUTE_WH;
create database if not exists prj13_db;
use database prj13_db;

create schema if not exists schema_comparison;
use schema schema_comparison;

create or replace file format retail_csv_format
    type = csv
    field_delimiter = ','
    skip_header = 1
    null_if = ('null', 'null', '')
    field_optionally_enclosed_by = '"';

create or replace stage retail_stage
    file_format = retail_csv_format;

create or replace transient table stg_regions_and_stores (
    store_id         number,
    store_name       varchar(100),
    city             varchar(50),
    state            varchar(50),
    region_name      varchar(50),
    regional_manager varchar(100)
);

create or replace transient table stg_product_hierarchy (
    product_id       number,
    product_name     varchar(100),
    subcategory_name varchar(50),
    category_name    varchar(50),
    unit_price       number(10,2)
);

create or replace transient table stg_sales_transactions (
    transaction_id   varchar(50),
    transaction_date date,
    customer_id      number,
    store_id         number,
    product_id       number,
    quantity         number,
    unit_price       number(10,2)
);

-- upload csv files using snowsql / web ui into @retail_stage, then load staging tables:
copy into stg_regions_and_stores from @retail_stage/regions_and_stores.csv;
copy into stg_product_hierarchy from @retail_stage/product_hierarchy.csv;
copy into stg_sales_transactions from @retail_stage/sales_transactions.csv;

create or replace table star_dim_store (
    store_key        number autoincrement primary key,
    store_id         number,
    store_name       varchar(100),
    city             varchar(50),
    state            varchar(50),
    region_name      varchar(50),
    regional_manager varchar(100)
);

create or replace table star_dim_product (
    product_key      number autoincrement primary key,
    product_id       number,
    product_name     varchar(100),
    subcategory_name varchar(50),
    category_name    varchar(50),
    unit_price       number(10,2)
);

insert into star_dim_store (store_id, store_name, city, state, region_name, regional_manager)
select store_id, store_name, city, state, region_name, regional_manager
from stg_regions_and_stores;

insert into star_dim_product (product_id, product_name, subcategory_name, category_name, unit_price)
select product_id, product_name, subcategory_name, category_name, unit_price
from stg_product_hierarchy;

create or replace table star_fact_sales (
    sales_key        number autoincrement primary key,
    transaction_id   varchar(50),
    transaction_date date,
    customer_id      number,
    store_key        number references star_dim_store(store_key),
    product_key      number references star_dim_product(product_key),
    quantity         number,
    total_amount     number(12,2)
);

insert into star_fact_sales (transaction_id, transaction_date, customer_id, store_key, product_key, quantity, total_amount)
select 
    st.transaction_id,
    st.transaction_date,
    st.customer_id,
    ds.store_key,
    dp.product_key,
    st.quantity,
    (st.quantity * st.unit_price) as total_amount
from stg_sales_transactions st
join star_dim_store ds on st.store_id = ds.store_id
join star_dim_product dp on st.product_id = dp.product_id;

create or replace table snow_dim_region (
    region_key       number autoincrement primary key,
    region_name      varchar(50),
    regional_manager varchar(100)
);

create or replace table snow_dim_store (
    store_key   number autoincrement primary key,
    store_id    number,
    store_name  varchar(100),
    city        varchar(50),
    state       varchar(50),
    region_key  number references snow_dim_region(region_key)
);

create or replace table snow_dim_category (
    category_key  number autoincrement primary key,
    category_name varchar(50)
);

create or replace table snow_dim_subcategory (
    subcategory_key  number autoincrement primary key,
    subcategory_name varchar(50),
    category_key     number references snow_dim_category(category_key)
);

create or replace table snow_dim_product (
    product_key     number autoincrement primary key,
    product_id      number,
    product_name    varchar(100),
    unit_price      number(10,2),
    subcategory_key number references snow_dim_subcategory(subcategory_key)
);

insert into snow_dim_region (region_name, regional_manager)
select distinct region_name, regional_manager
from stg_regions_and_stores;

insert into snow_dim_store (store_id, store_name, city, state, region_key)
select 
    s.store_id, 
    s.store_name, 
    s.city, 
    s.state, 
    r.region_key
from stg_regions_and_stores s
join snow_dim_region r on s.region_name = r.region_name;

insert into snow_dim_category (category_name)
select distinct category_name
from stg_product_hierarchy;

insert into snow_dim_subcategory (subcategory_name, category_key)
select distinct 
    p.subcategory_name, 
    c.category_key
from stg_product_hierarchy p
join snow_dim_category c on p.category_name = c.category_name;

insert into snow_dim_product (product_id, product_name, unit_price, subcategory_key)
select 
    p.product_id, 
    p.product_name, 
    p.unit_price, 
    sc.subcategory_key
from stg_product_hierarchy p
join snow_dim_subcategory sc on p.subcategory_name = sc.subcategory_name;

create or replace table snow_fact_sales (
    sales_key        number autoincrement primary key,
    transaction_id   varchar(50),
    transaction_date date,
    customer_id      number,
    store_key        number references snow_dim_store(store_key),
    product_key      number references snow_dim_product(product_key),
    quantity         number,
    total_amount     number(12,2)
);

insert into snow_fact_sales (transaction_id, transaction_date, customer_id, store_key, product_key, quantity, total_amount)
select 
    st.transaction_id,
    st.transaction_date,
    st.customer_id,
    ds.store_key,
    dp.product_key,
    st.quantity,
    (st.quantity * st.unit_price) as total_amount
from stg_sales_transactions st
join snow_dim_store ds on st.store_id = ds.store_id
join snow_dim_product dp on st.product_id = dp.product_id;

select 
    dst.region_name,
    dp.category_name,
    sum(f.total_amount) as total_revenue
from star_fact_sales f
join star_dim_store dst on f.store_key = dst.store_key
join star_dim_product dp on f.product_key = dp.product_key
group by dst.region_name, dp.category_name
order by dst.region_name asc, dp.category_name asc;

select 
    r.region_name,
    c.category_name,
    sum(f.total_amount) as total_revenue
from snow_fact_sales f
join snow_dim_store s on f.store_key = s.store_key
join snow_dim_region r on s.region_key = r.region_key
join snow_dim_product p on f.product_key = p.product_key
join snow_dim_subcategory sc on p.subcategory_key = sc.subcategory_key
join snow_dim_category c on sc.category_key = c.category_key
group by r.region_name, c.category_name
order by r.region_name asc, c.category_name asc;

select * from (
    select 'dimension normalization level' as metric_feature, 'denormalized (flat)' as star_schema, 'normalized (hierarchical)' as snowflake_schema union all
    select 'total dimension tables', '2 tables', '5 tables' union all
    select 'joins for category revenue', '2 joins (fact + 2 dims)', '4 joins (fact + 4 dims)' union all
    select 'data redundancy', 'higher (repeated text)', 'lower (normalized ids)' union all
    select 'query simplicity', 'high (simple group by)', 'lower (requires nested fks)'
);

select 
    dst.regional_manager,
    sum(f.quantity) as total_items_sold,
    sum(f.total_amount) as total_sales_amount
from star_fact_sales f
join star_dim_store dst on f.store_key = dst.store_key
group by dst.regional_manager
order by total_sales_amount desc;

select 'star schema' as schema_type, 'star_dim_store' as table_name, count(*) as record_count from star_dim_store
union all
select 'star schema', 'star_dim_product', count(*) from star_dim_product
union all
select 'star schema', 'star_fact_sales', count(*) from star_fact_sales
union all
select 'snowflake schema', 'snow_dim_region', count(*) from snow_dim_region
union all
select 'snowflake schema', 'snow_dim_store', count(*) from snow_dim_store
union all
select 'snowflake schema', 'snow_dim_category', count(*) from snow_dim_category
union all
select 'snowflake schema', 'snow_dim_subcategory', count(*) from snow_dim_subcategory
union all
select 'snowflake schema', 'snow_dim_product', count(*) from snow_dim_product
union all
select 'snowflake schema', 'snow_fact_sales', count(*) from snow_fact_sales;