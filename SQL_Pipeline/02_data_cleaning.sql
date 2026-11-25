-- 02_data_cleaning.sql
-- UK National Rail Project: Data Standardization, Missing Value Handling & Feature Engineering (T-SQL)

-- Drop cleaned table if it already exists
DROP TABLE IF EXISTS clean_railway_journeys;

-- Create cleaned journeys table with explicit constraints and T-SQL data types
CREATE TABLE clean_railway_journeys (
    transaction_id VARCHAR(50) NOT NULL,
    date_of_purchase DATE NOT NULL,
    time_of_purchase TIME(0) NOT NULL,
    purchase_type VARCHAR(20) NOT NULL,
    payment_method VARCHAR(30) NOT NULL,
    railcard VARCHAR(20) NOT NULL,
    ticket_class VARCHAR(20) NOT NULL,
    ticket_type VARCHAR(20) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    departure_station VARCHAR(100) NOT NULL,
    arrival_destination VARCHAR(100) NOT NULL,
    date_of_journey DATE NOT NULL,
    departure_time TIME(0) NOT NULL,
    arrival_time TIME(0) NOT NULL,
    actual_arrival_time TIME(0) NULL,
    journey_status VARCHAR(20) NOT NULL,
    reason_for_delay VARCHAR(100) NOT NULL,
    refund_request VARCHAR(10) NOT NULL,
    lead_time_days INT NOT NULL,
    scheduled_duration_minutes INT NOT NULL,
    delay_minutes INT NULL,
    journey_route VARCHAR(250) NOT NULL,
    CONSTRAINT pk_clean_railway PRIMARY KEY (transaction_id),
    CONSTRAINT chk_clean_price CHECK (price >= 0),
    CONSTRAINT chk_clean_lead_time CHECK (lead_time_days >= 0),
    CONSTRAINT chk_clean_duration CHECK (scheduled_duration_minutes >= 0)
);

-- Populate clean_railway_journeys with standardized values and derived analytical fields
INSERT INTO clean_railway_journeys (
    transaction_id,
    date_of_purchase,
    time_of_purchase,
    purchase_type,
    payment_method,
    railcard,
    ticket_class,
    ticket_type,
    price,
    departure_station,
    arrival_destination,
    date_of_journey,
    departure_time,
    arrival_time,
    actual_arrival_time,
    journey_status,
    reason_for_delay,
    refund_request,
    lead_time_days,
    scheduled_duration_minutes,
    delay_minutes,
    journey_route
)
SELECT
    LTRIM(RTRIM(transaction_id)) AS transaction_id,
    CAST(date_of_purchase AS DATE) AS date_of_purchase,
    CAST(time_of_purchase AS TIME(0)) AS time_of_purchase,
    LTRIM(RTRIM(purchase_type)) AS purchase_type,
    LTRIM(RTRIM(payment_method)) AS payment_method,
    COALESCE(NULLIF(LTRIM(RTRIM(railcard)), ''), 'None') AS railcard,
    LTRIM(RTRIM(ticket_class)) AS ticket_class,
    LTRIM(RTRIM(ticket_type)) AS ticket_type,
    CAST(price AS DECIMAL(10, 2)) AS price,
    LTRIM(RTRIM(departure_station)) AS departure_station,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(arrival_destination))) = 'EDINBURGH' THEN 'Edinburgh Waverley'
        ELSE LTRIM(RTRIM(arrival_destination))
    END AS arrival_destination,
    CAST(date_of_journey AS DATE) AS date_of_journey,
    CAST(departure_time AS TIME(0)) AS departure_time,
    CAST(arrival_time AS TIME(0)) AS arrival_time,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(journey_status))) = 'CANCELLED' THEN NULL
        ELSE TRY_CAST(NULLIF(LTRIM(RTRIM(actual_arrival_time)), '') AS TIME(0))
    END AS actual_arrival_time,
    LTRIM(RTRIM(journey_status)) AS journey_status,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(journey_status))) = 'ON TIME' THEN 'None / No Delay'
        WHEN UPPER(LTRIM(RTRIM(reason_for_delay))) IN ('WEATHER', 'WEATHER CONDITIONS') THEN 'Weather'
        WHEN UPPER(LTRIM(RTRIM(reason_for_delay))) IN ('STAFFING', 'STAFF SHORTAGE') THEN 'Staffing'
        WHEN UPPER(LTRIM(RTRIM(reason_for_delay))) = 'SIGNAL FAILURE' THEN 'Signal Failure'
        WHEN UPPER(LTRIM(RTRIM(reason_for_delay))) = 'TECHNICAL ISSUE' THEN 'Technical Issue'
        WHEN UPPER(LTRIM(RTRIM(reason_for_delay))) = 'TRAFFIC' THEN 'Traffic'
        WHEN reason_for_delay IS NULL OR LTRIM(RTRIM(reason_for_delay)) = '' THEN 'None / No Delay'
        ELSE LTRIM(RTRIM(reason_for_delay))
    END AS reason_for_delay,
    LTRIM(RTRIM(refund_request)) AS refund_request,
    -- Lead time in days between purchase date and journey date
    DATEDIFF(DAY, CAST(date_of_purchase AS DATE), CAST(date_of_journey AS DATE)) AS lead_time_days,
    -- Scheduled trip duration handling overnight arrivals crossing midnight
    CASE 
        WHEN CAST(arrival_time AS TIME) >= CAST(departure_time AS TIME) THEN
            DATEDIFF(MINUTE, CAST(departure_time AS TIME), CAST(arrival_time AS TIME))
        ELSE
            DATEDIFF(MINUTE, CAST(departure_time AS TIME), CAST(arrival_time AS TIME)) + 1440
    END AS scheduled_duration_minutes,
    -- Arrival delay handling overnight actual arrivals crossing midnight
    CASE 
        WHEN UPPER(LTRIM(RTRIM(journey_status))) = 'CANCELLED' THEN NULL
        WHEN actual_arrival_time IS NULL OR LTRIM(RTRIM(actual_arrival_time)) = '' THEN NULL
        WHEN TRY_CAST(actual_arrival_time AS TIME) IS NULL THEN NULL
        WHEN TRY_CAST(actual_arrival_time AS TIME) >= CAST(arrival_time AS TIME) THEN
            DATEDIFF(MINUTE, CAST(arrival_time AS TIME), TRY_CAST(actual_arrival_time AS TIME))
        ELSE
            DATEDIFF(MINUTE, CAST(arrival_time AS TIME), TRY_CAST(actual_arrival_time AS TIME)) + 1440
    END AS delay_minutes,
    -- Unified journey corridor route
    CONCAT(
        LTRIM(RTRIM(departure_station)), 
        ' -> ', 
        CASE 
            WHEN UPPER(LTRIM(RTRIM(arrival_destination))) = 'EDINBURGH' THEN 'Edinburgh Waverley'
            ELSE LTRIM(RTRIM(arrival_destination))
        END
    ) AS journey_route
FROM stg_railway_raw;

-- Deduplication: Remove potential duplicate rows using valid T-SQL CTE syntax
WITH cte_duplicates AS (
    SELECT 
        transaction_id,
        ROW_NUMBER() OVER (
            PARTITION BY transaction_id 
            ORDER BY date_of_purchase, time_of_purchase, date_of_journey
        ) AS rn
    FROM clean_railway_journeys
)
DELETE FROM cte_duplicates
WHERE rn > 1;

-- Verification Check 1: Row count preservation check (Expected: 31,653)
SELECT 
    COUNT(*) AS total_cleaned_rows,
    CASE WHEN COUNT(*) = 31653 THEN 'PASSED' ELSE 'FAILED' END AS row_count_check
FROM clean_railway_journeys;

-- Verification Check 2: Null and constraint validity checks
SELECT
    SUM(CASE WHEN transaction_id IS NULL THEN 1 ELSE 0 END) AS null_transaction_ids,
    SUM(CASE WHEN railcard IS NULL THEN 1 ELSE 0 END) AS null_railcards,
    SUM(CASE WHEN reason_for_delay IS NULL THEN 1 ELSE 0 END) AS null_delay_reasons,
    SUM(CASE WHEN price IS NULL OR price <= 0 THEN 1 ELSE 0 END) AS invalid_prices,
    SUM(CASE WHEN lead_time_days IS NULL OR lead_time_days < 0 THEN 1 ELSE 0 END) AS invalid_lead_times
FROM clean_railway_journeys;

-- Verification Check 3: Standardized delay reason categories (Expected: 6 categories)
SELECT 
    reason_for_delay,
    COUNT(*) AS record_count
FROM clean_railway_journeys
GROUP BY reason_for_delay
ORDER BY record_count DESC;

-- Verification Check 4: Cancelled journeys actual arrival null consistency
SELECT 
    journey_status,
    COUNT(*) AS total_records,
    SUM(CASE WHEN actual_arrival_time IS NULL THEN 1 ELSE 0 END) AS null_actual_arrivals,
    SUM(CASE WHEN delay_minutes IS NULL THEN 1 ELSE 0 END) AS null_delay_minutes
FROM clean_railway_journeys
GROUP BY journey_status
ORDER BY total_records DESC;

-- Verification Check 5: Station naming standardization check (Expected: 0 unmapped)
SELECT 
    COUNT(*) AS unmapped_edinburgh_count,
    CASE WHEN COUNT(*) = 0 THEN 'PASSED' ELSE 'FAILED' END AS edinburgh_normalization_check
FROM clean_railway_journeys
WHERE UPPER(LTRIM(RTRIM(arrival_destination))) = 'EDINBURGH';
