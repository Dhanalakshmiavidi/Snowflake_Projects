create warehouse datalake_14
warehouse_size='xsmall'
auto_suspend=60
auto_resume=true;

create database lake_db;
create schema lake_schema;

use database lake_db;
use schema lake_schema;

create file format json
type=json;

create stage lake_stage1;

create table events(
raw_event variant);

copy into events
from @lake_stage1
file_format=(format_name=json_forma);

CREATE OR REPLACE FILE FORMAT json_format
TYPE = JSON
STRIP_OUTER_ARRAY = FALSE;

SELECT $1
FROM @lake_stage1
(FILE_FORMAT => json_format);

insert into events 
select $1 from @lake_stage1
(file_format=> json_format)
where $1:event_id::string <>'INVALID_JSON_PAYLOAD_MALFORMED_STRING';

--TASK 1: Data Lake Ingestion
select count(*) as total_Count from events;
//11

--TASK 2: Schema-on-Read Ingestion & Extraction
select raw_event:event_id::varchar as event_id,
raw_event:timestamp::timestamp as event_time,
raw_event:user_id::number as user_id,
raw_event:action::varchar as action,
raw_event:order.total::number(12,2) as order_total,
raw_event:promo_code::varchar as promo_code,
from events order by event_time;
-- EVT-8001	2026-07-01 08:15:00.000	1001	purchase	12500.00	
-- EVT-8002	2026-07-01 08:20:00.000	1002	view		
-- EVT-8003	2026-07-01 08:35:00.000	1003	add_to_cart		
-- EVT-8004	2026-07-01 09:10:00.000	1004	purchase	45000.00	
-- EVT-8005	2026-07-01 09:45:00.000	1001	view		
-- EVT-8006	2026-07-02 10:00:00.000	1005	purchase	18000.00	SUMMER20
-- EVT-8007	2026-07-02 10:15:00.000	1002	purchase	8500.00	WELCOME10
-- EVT-8008	2026-07-02 10:30:00.000	1006	add_to_cart		
-- EVT-8009	2026-07-02 11:00:00.000	1003	purchase	32000.00	FESTIVE15
-- EVT-8010	2026-07-02 11:20:00.000	1007	view		
-- EVT-8011	2026-07-03 12:00:00.000	1008	purchase	0.00	FREEPASS

-- TASK 3: Schema-on-Read Financial Analysis
-- - Calculate `NET_REVENUE` for orders where `total > 0`.
-- - Formula: `NET_REVENUE = ORDER_TOTAL - SHIPPING_COST - TAX - COALESCE(DISCOUNT_AMOUNT, 0)`
select raw_event:event_id::varchar as event_id,
raw_event:order.total::number(12,2) as order_total,
raw_event:order.shipping_cost::number(12,2) as shipping_cost,
raw_event:order.tax::number(12,2) as tax,
coalesce(raw_event:discount_amount::number(12,2),0) as discount_amount,
raw_event:order.total::number(12,2)-
raw_event:order.shipping_cost::number(12,2)-
raw_event:order.tax::number(12,2)-
coalesce(raw_event:discount_amount::number(12,2),0) as total_revenue
from events
where raw_event:order.total::number(12,2)>0
order by event_id;

-- EVT-8001	12500.00	250.00	625.00	0.00	11625.00
-- EVT-8004	45000.00	500.00	2250.00	0.00	42250.00
-- EVT-8006	18000.00	300.00	900.00	3600.00	13200.00
-- EVT-8007	8500.00	150.00	425.00	850.00	7075.00
-- EVT-8009	32000.00	400.00	1600.00	4800.00	25200.00

-- TASK 4: Funnel & Conversion Key Metrics
-- - Compute high-level business KPIs across valid non-zero events.
select count(*) as total_events,
count_if(raw_event:action::varchar='purchase'
and raw_event:order.total::number>0) as total_purchases,
round(count_if(raw_event:action::varchar='purchase' 
and raw_event:order.total::number>0)*100.0/count(*),2) as conversion_rate_pct,
sum(case when raw_event:action::varchar='purchase' and raw_event:order.total::number>0
         then raw_event:order.total::number(12,2)
         else 0
    end
    )as total_gross_revenue,
round(sum(case when raw_event:action::varchar='purchase' and raw_event:order.total::number>0
               then raw_event:order.total::number(12,2)
               else 0
          end)/count_if(raw_event:action::varchar='purchase'
          and raw_event:order.total::number>0),2) as average_order_value
from events;
--TOTAL_EVENTS   TOTAL_PURCHASES  CONVERSION_RATE_PCT  TOTAL_GROSS_REVENUE  AVERAGE_ORDER_VALUE
--     11	               5	               45.45	       116000.00	        23200.00

--TASK 5: Data Warehouse Backfill (Schema-on-Write)
create table dw_events(
event_id varchar(20),
event_time timestamp,
user_id number,
page varchar(20),
action varchar(20),
order_total number(12,2),
shipping_cost number(12,2),
tax number(12,2),
items number,
promo_code varchar(20),
discount number(12,2),
net_revenue number(12,2));

--- Insert valid extracted payloads into `DW_STRUCTURED_EVENTS`.
insert into dw_events(event_id,event_time,user_id ,page ,action ,order_total ,
shipping_cost ,tax ,items ,promo_code ,discount ,net_revenue)
select raw_event:event_id::varchar,
raw_event:timestamp::timestamp,
raw_event:user_id::number ,
raw_event:page::varchar,
raw_event:action::varchar ,
raw_event:order.total::number(12,2),
raw_event:order.shipping_cost::number(12,2),
raw_event:order.tax::number(12,2),
raw_event:order.items::number,
raw_event:promo_code::varchar,
coalesce(raw_event:discount_amount::number(12,2),0),

coalesce(raw_event:order.total::number(12,2),0)-
coalesce(raw_event:order.shipping_cost::number(12,2),0)-
coalesce(raw_event:order.tax::number(12,2),0)-
coalesce(raw_event:discount_amount::number(12,2),0)
from events;

select count(*) AS stored_records_qty,
sum(net_revenue) AS total_net_revenue
from dw_events;
--STORED_RECORDS_QTY    TOTAL_NET_REVENUE
--            11	    99350.00

--TASK 6: Data Integrity & Error Quarantine Strategy
--Identify and move corrupt non-JSON records into `QUARANTINE_RAW_EVENTS`.
create table quarantine_events(quarantine_id number autoincrement primary key,
raw_record_text varchar,
reason varchar(50));

SELECT $1
FROM @lake_stage1/events.json
(FILE_FORMAT => json_format);

insert into quarantine_events(raw_record_text, reason)
select $1::varchar,'MALFORMED_JSON_BODY'
from @lake_stage1/events.json
(file_format => json_format)
where $1:event_id::varchar = 'INVALID_JSON_PAYLOAD_MALFORMED_STRING';

select * from quarantine_events;