CREATE or REPLACE WAREHOUSE hospital
WITH
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
--TASK 1 — Create Database and Schema Context
create or replace database healthcare_dw;
create or replace schema schema_lab;

use database healthcare_dw;
use schema schema_lab;

create file format csv_format
type=csv
field_delimiter=','
skip_header=1;

create stage hospital_stage;

create table hospital(
hospital_id number,
hospital_name varchar(30),
city varchar(30),
state varchar(30),
network_id number,
network_name varchar(30),
network_director varchar(30));

create table treatment(
treatment_id number,
treatment_name varchar(30),
diagnosis_group_id varchar(30),
diagnosis_group_name varchar(30),
standard_cost number(12,2));

create table patient(
patient_id number,
patient_name varchar(30),
gender varchar(10),
age number,
city varchar(30));

create table insurance(
claim_id varchar(20),
claim_date date,
patient_id number,
hospital_id number,
treatment_id number,
claimed_amount number(12,2),
approved_amount number(12,2));

copy into hospital
from @hospital_stage/hospital.csv
file_format=csv_format;

copy into treatment
from @hospital_stage/treatment.csv
file_format=csv_format;

copy into patient
from @hospital_stage/patient.csv
file_format=csv_format;

copy into insurance
from @hospital_stage/insurance.csv
file_format=csv_format;

--TASK 2 — Build Star Schema Denormalized Hospital Dimension (`STAR_DIM_HOSPITAL`)
create table star_dim_hospital(
hospital_key number autoincrement primary key,
hospital_id number,
hospital_name varchar(30),
city varchar(30),
state varchar(30),
network_name varchar(30),
network_director varchar(30));

--TASK 3 — Build Star Schema Denormalized Treatment Dimension (`STAR_DIM_TREATMENT`)
create table star_dim_treatment(
treatment_key number autoincrement primary key,
treatment_id number,
treatment_name varchar(30),
diagnosis_group_name varchar(30),
standard_cost number(12,2));

--TASK 4 — Load Star Schema Dimension Data
insert into star_dim_hospital(hospital_id ,hospital_name ,city ,state ,network_name ,network_director)
select hospital_id ,hospital_name ,city ,state ,network_name ,network_director from hospital;
-- number of rows inserted
-- 3

insert into star_dim_treatment(treatment_id,treatment_name ,diagnosis_group_name,standard_cost)
select treatment_id,treatment_name ,diagnosis_group_name,standard_cost from treatment;
-- number of rows inserted
-- 3

--TASK 5 — Build & Load Star Schema Claims Fact Table (`STAR_FACT_CLAIMS`)
create table star_fact_claims(
claim_key number autoincrement primary key,
claim_id varchar(20),
claim_date date,
patient_id number,
hospital_key number,
treatment_key number,
claimed_amount number(12,2),
approved_amount number(12,2),
foreign key(hospital_key) references star_dim_hospital(hospital_key),
foreign key(treatment_key) references star_dim_treatment(treatment_key));

insert into star_fact_claims(claim_id,claim_date,patient_id,hospital_key,treatment_key,claimed_amount,approved_amount)
select c.claim_id,c.claim_date,c.patient_id,h.hospital_key,t.treatment_key,
c.claimed_amount,c.approved_amount from insurance c join star_dim_hospital h on c.hospital_id=h.hospital_id
join star_dim_treatment t on c.treatment_id=t.treatment_id;

--TASK 6 — Build Normalized Snowflake Schema Hospital Hierarchy
create table snow_dim_network(network_key number autoincrement primary key,
network_id number,
network_name varchar(30),
network_director varchar(30));

create table snow_dim_hospital(
hospital_key number autoincrement primary key,
hospital_id number,
hospital_name varchar(30),
city varchar(30),
state varchar(30),
network_key number,
foreign key(network_key) references snow_dim_network(network_key));
--TASK 7 — Build Normalized Snowflake Schema Treatment Hierarchy
create table snow_dim_diagnosis_group(diagnosis_group_key number autoincrement primary key,
diagnosis_group_id varchar(30),
diagnosis_group_name varchar(30));

create table snow_dim_treatment(treatment_key number autoincrement primary key,
treatment_id number,
treatment_name varchar(30),
standard_cost number(12,2),
diagnosis_group_key number,
foreign key(diagnosis_group_key) references snow_dim_diagnosis_group(diagnosis_group_key));

--TASK 8 — Populate Snowflake Schema Normalized Hierarchies
insert into snow_dim_network(network_id,network_name,network_director)
select distinct network_id,network_name,network_director from hospital;

insert into snow_dim_hospital(hospital_id,hospital_name,city,state,network_key)
select hospital_id,hospital_name,city,state,n.network_key from hospital h join
snow_dim_network n on h.network_name=n.network_name;

insert into snow_dim_diagnosis_group(diagnosis_group_id,diagnosis_group_name)
select diagnosis_group_id,diagnosis_group_name from treatment;

insert into snow_dim_treatment(treatment_id,treatment_name,standard_cost,diagnosis_group_key)
select t.treatment_id,t.treatment_name,t.standard_cost,d.diagnosis_group_key from treatment t
join snow_dim_diagnosis_group d on t.diagnosis_group_id=d.diagnosis_group_id;

--TASK 9 — Build & Load Snowflake Schema Claims Fact Table (`SNOW_FACT_CLAIMS`)
create table snow_fact_claims(
claim_key number autoincrement primary key,
claim_id varchar(20),
claim_date date,
patient_id number,
hospital_key number,
treatment_key number,
claimed_amount number(12,2),
approved_amount number(12,2),
foreign key(hospital_key) references snow_dim_hospital(hospital_key),
foreign key(treatment_key) references snow_dim_treatment(treatment_key));

insert into snow_fact_claims(claim_id,claim_date,
patient_id,hospital_key,treatment_key,claimed_amount,approved_amount)
select i.claim_id,i.claim_date,i.patient_id,h.hospital_key,t.treatment_key,
i.claimed_amount,i.approved_amount from insurance i join snow_dim_hospital h
on i.hospital_id=h.hospital_id
join snow_dim_treatment t on i.treatment_id=t.treatment_id;

--TASK 10 — Star Schema Specialty Claims Analysis (Flat 1-Hop Query)
select d.diagnosis_group_name,sum(f.claimed_amount) as total_claimed_amount,sum(f.approved_amount) as total_approved_amount from
star_fact_claims f join star_dim_treatment d on f.treatment_key=d.treatment_key
group by d.diagnosis_group_name order by total_approved_amount desc ;
-- Cardiology	160000.00	150000.00
-- General Surgery	98000.00	90000.00
-- Orthopedics	230000.00	22000.00

--TASK 11 — Snowflake Schema Specialty Claims Analysis (Multi-Hop Join Query)
select d.diagnosis_group_name,sum(f.claimed_amount) as total_claimed_amount,sum(f.approved_amount) as total_approved_amount from
snow_fact_claims f join snow_dim_treatment t on f.treatment_key=t.treatment_key
join snow_dim_diagnosis_group d on t.diagnosis_group_key=d.diagnosis_group_key
group by d.diagnosis_group_name order by total_approved_amount desc ;
-- Cardiology	160000.00	150000.00
-- General Surgery	98000.00	90000.00
-- Orthopedics	230000.00	22000.00

--TASK 12 — Hospital Network Director Performance Report using star and snowflake schemas
select h.network_director,count(f.claim_key) as total_claims_handled,sum(f.approved_amount) as total_approved_amount
from star_fact_claims f join star_dim_hospital h on f.hospital_key=h.hospital_key
group by h.network_director order by total_approved_amount desc;

select n.network_director,count(f.claim_key) as total_claims_handled,
sum(f.approved_amount) as total_approved_amount from snow_fact_claims f 
join snow_dim_hospital h on f.hospital_key=h.hospital_key
join snow_dim_network n on h.network_key=n.network_key
group by n.network_director order by total_approved_amount desc;
-- Dr. Anand	3	240000.00
-- Dr. Priya	1	22000.00

--TASK 13 — Data Anomaly Analysis: Master Data Update Test (Network Director Update)
update star_dim_hospital set network_director='Dr. Anand'
where network_name='Apollo Healthcare Group';
-- number of rows updated
-- 2
--This updates 2 rows because both Apollo hospitals contain the director name.
select * from star_dim_hospital where network_director='Dr. Anand';
-- 1	1001	Apollo Jubilee Hills	Hyderabad	Telangana	Apollo Healthcare Group	Dr. Anand
-- 2	1002	Apollo Reach	Warangal	Telangana	Apollo Healthcare Group	Dr. Anand

update snow_dim_network set network_director='Dr. Anand'
where network_id=10;
-- number of rows updated
-- 1
--This updates 1 row because the director is stored once at the network level.
select * from snow_dim_network where network_director='Dr. Anand';
-- 2	10	Apollo Healthcare Group	Dr. Anand

select 'Star schema' as schema_type,'star_dim_hospital' as updated_table,
2 as rows_updated,'Higher (Multiple rows)' as maintenance_effort
union all
select 'Snowflake schema','snow_dim_network',1,'Lower (Single row)';
-- SCHEMA_TYPE       UPDATED_TABLE      ROWS_UPDATED  MAINTENANCE_EFFORT
-- -----------------------------------------------------------------------------
-- Star Schema       STAR_DIM_HOSPITAL  2             Higher (Multiple rows)
-- Snowflake Schema  SNOW_DIM_NETWORK   1             Lower (Single row)

--TASK 14 — Full Architecture Record Audit & Schema Comparison
select 'Star schema' as schema_type,'STAR_DIM_HOSPITAL' as table_name,count(*) as record_count from STAR_DIM_HOSPITAL
union all
select 'Star schema','STAR_DIM_TREATMENT',count(*) from STAR_DIM_TREATMENT
union all
select 'Star schema','STAR_FACT_CLAIMS ',count(*) from STAR_FACT_CLAIMS 
union all
select 'Snowflake Schema', 'SNOW_DIM_NETWORK',count(*) from SNOW_DIM_NETWORK
union all
select 'Snowflake Schema','SNOW_DIM_HOSPITAL ', count(*) from SNOW_DIM_HOSPITAL
union all
select 'Snowflake Schema', 'SNOW_DIM_DIAGNOSIS_GROUP',count(*) from SNOW_DIM_DIAGNOSIS_GROUP
union all
select 'Snowflake Schema',  'SNOW_DIM_TREATMENT',count(*) from SNOW_DIM_TREATMENT    
union all
select 'Snowflake Schema', 'SNOW_FACT_CLAIMS',count(*) from SNOW_FACT_CLAIMS;