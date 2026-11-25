-- 01_schema_staging.sql
-- UK National Rail Project: Staging Table & Raw Data Ingestion (T-SQL)

-- Drop staging table if it already exists
DROP TABLE IF EXISTS stg_railway_raw;

-- Create staging table matching all 18 raw columns with T-SQL data types
-- Note: actual_arrival_time is set to VARCHAR(20) NULL to safely import empty strings from raw CSV
CREATE TABLE stg_railway_raw (
    transaction_id VARCHAR(50) NOT NULL,
    date_of_purchase DATE NOT NULL,
    time_of_purchase TIME(0) NOT NULL,
    purchase_type VARCHAR(20) NOT NULL,
    payment_method VARCHAR(30) NOT NULL,
    railcard VARCHAR(20) NULL,
    ticket_class VARCHAR(20) NOT NULL,
    ticket_type VARCHAR(20) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    departure_station VARCHAR(100) NOT NULL,
    arrival_destination VARCHAR(100) NOT NULL,
    date_of_journey DATE NOT NULL,
    departure_time TIME(0) NOT NULL,
    arrival_time TIME(0) NOT NULL,
    actual_arrival_time VARCHAR(20) NULL,
    journey_status VARCHAR(20) NOT NULL,
    reason_for_delay VARCHAR(100) NULL,
    refund_request VARCHAR(10) NOT NULL
);

-- Pre-load verification rules before executing BULK INSERT:
-- 1. Ensure date columns follow standard ISO format (YYYY-MM-DD).
-- 2. Ensure time columns follow standard 24-hour clock format (HH:MM:SS).
-- 3. Ensure price column contains clean numeric values with no currency symbols (e.g. £).
-- 4. Empty strings in railcard, reason_for_delay, and actual_arrival_time are preserved as NULL via KEEPNULLS.
-- 5. Row terminator: Use '\n' (0x0a) or '\r\n' matching the source CSV line-ending encoding.

-- T-SQL Bulk Insert command for importing raw CSV data into SQL Server
BULK INSERT stg_railway_raw
FROM 'D:\كتب\DEPI_R5_EL_FAYOUM_JDA\Capston_Project\railway.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    KEEPNULLS,
    TABLOCK
 );

-- Staging verification: Confirm total row count (Expected: 31,653)
SELECT COUNT(*) AS raw_row_count FROM stg_railway_raw;

-- Sample record inspection using TOP
SELECT TOP (5)
    transaction_id,
    date_of_purchase,
    purchase_type,
    payment_method,
    railcard,
    ticket_class,
    ticket_type,
    price,
    departure_station,
    arrival_destination,
    date_of_journey,
    journey_status,
    reason_for_delay,
    refund_request
FROM stg_railway_raw;
