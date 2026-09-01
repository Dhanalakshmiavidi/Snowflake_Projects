
CREATE OR REPLACE DATABASE medallion_db;
CREATE OR REPLACE SCHEMA medallion_db.med_schema;

USE DATABASE medallion_db;
USE SCHEMA med_schema;

CREATE OR REPLACE FILE FORMAT json_format
    TYPE = JSON
    STRIP_OUTER_ARRAY = FALSE;

CREATE OR REPLACE STAGE lakehouse 
    FILE_FORMAT = json_format;


-- BRONZE LAYER SETUP 
CREATE OR REPLACE TABLE bronze (
    raw_txn VARIANT,
    ingested_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());

-- Load the raw JSON file from the internal stage
COPY INTO bronze (raw_txn) 
FROM @lakehouse/raw_bronze.json
FILE_FORMAT = (FORMAT_NAME = json_format)
FORCE = TRUE;

-- Verify Bronze ingestion
SELECT * FROM bronze;

SELECT COUNT(*) AS total_bronze_records_ct FROM bronze;


--  SILVER LAYER ETL & FEE COMPUTATIONS (CLEANSED & MASKED)
CREATE OR REPLACE TABLE silver (
    txn_id VARCHAR(20) PRIMARY KEY,
    txn_time TIMESTAMP_TZ,
    merchant_id NUMBER,
    merchant_name VARCHAR(50),
    card_number VARCHAR(25),
    gross_amount NUMBER(12,2),
    fee_pct NUMBER(5,2),
    processing_fee NUMBER(12,2),
    net_settlement_amount NUMBER(12,2),
    status VARCHAR(20));

INSERT INTO silver (
    txn_id,
    txn_time,
    merchant_id,
    merchant_name,
    card_number,
    gross_amount,
    fee_pct,
    processing_fee,
    net_settlement_amount,
    status)
SELECT 
    raw_txn:txn_id::VARCHAR,
    raw_txn:txn_time::TIMESTAMP_TZ,
    raw_txn:merchant_id::NUMBER,
    raw_txn:merchant_name::VARCHAR,
    'XXXX-XXXX-XXXX-' || RIGHT(raw_txn:card_number::VARCHAR, 4),
    raw_txn:amount::NUMBER(12,2),
    raw_txn:fee_pct::NUMBER(5,2),
    ROUND(raw_txn:amount::NUMBER(12,2) * (raw_txn:fee_pct::NUMBER(5,2) / 100), 2),
    ROUND(raw_txn:amount::NUMBER(12,2) - (raw_txn:amount::NUMBER(12,2) * (raw_txn:fee_pct::NUMBER(5,2) / 100)), 2),
    raw_txn:status::VARCHAR
FROM bronze;

-- Verify Silver transformed records
SELECT 
    txn_id, 
    merchant_id, 
    merchant_name, 
    card_number, 
    gross_amount, 
    fee_pct, 
    processing_fee, 
    net_settlement_amount, 
    status 
FROM silver
ORDER BY txn_id;


--GOLD LAYER AGGREGATIONS
CREATE OR REPLACE TABLE gold (
    merchant_id NUMBER PRIMARY KEY,
    merchant_name VARCHAR(50),
    total_approved_gross NUMBER(12,2),
    total_gateway_fees NUMBER(12,2),
    total_net_payout NUMBER(12,2),
    approved_count NUMBER);

INSERT INTO gold (
    merchant_id,
    merchant_name,
    total_approved_gross,
    total_gateway_fees,
    total_net_payout,
    approved_count)
SELECT 
    merchant_id,
    merchant_name,
    SUM(gross_amount),
    SUM(processing_fee),
    SUM(net_settlement_amount),
    COUNT(*)
FROM silver
WHERE status = 'APPROVED'
GROUP BY merchant_id, merchant_name;

-- Verify Gold layer aggregations
SELECT * FROM gold ORDER BY merchant_id;


--DATA CORRUPTION SIMULATION & TIME-TRAVEL INSPECTION
UPDATE silver 
SET status = 'REFUNDED' 
WHERE merchant_name = 'TechZone' AND status = 'APPROVED';

-- 2. View corrupted state in current table
SELECT txn_id, merchant_name, gross_amount, status 
FROM silver
WHERE merchant_name = 'TechZone' 
ORDER BY txn_id;

-- 3. Query historical snapshot before the corruption using Time-Travel
SELECT txn_id, merchant_name, gross_amount, status
FROM silver AT (OFFSET => -60)
WHERE merchant_name = 'TechZone'
ORDER BY txn_id;


-- Restore corrupted statuses using historical state from Time-Travel
UPDATE silver s
SET s.status = hist.status
FROM (
    SELECT txn_id, status 
    FROM silver AT (OFFSET => -60)
    WHERE merchant_name = 'TechZone' AND status = 'APPROVED') hist
WHERE s.txn_id = hist.txn_id;

-- Verify recovery status
SELECT 
    merchant_name,
    COUNT_IF(status = 'APPROVED') AS approved_count,
    COUNT_IF(status = 'REFUNDED') AS refunded_count
FROM silver 
WHERE merchant_name = 'TechZone' 
GROUP BY merchant_name;


-- END-TO-END PIPELINE RECONCILIATION AUDIT
SELECT 
    (SELECT SUM(raw_txn:amount::NUMBER(12,2)) FROM bronze) AS bronze_gross_sum,
    (SELECT SUM(gross_amount) FROM silver) AS silver_gross_sum,
    (SELECT SUM(total_approved_gross) FROM gold) AS gold_gross_sum,
    CASE 
        WHEN (SELECT SUM(raw_txn:amount::NUMBER(12,2)) FROM bronze) = (SELECT SUM(gross_amount) FROM silver)
        THEN TRUE 
        ELSE FALSE 
    END AS data_match_flag;