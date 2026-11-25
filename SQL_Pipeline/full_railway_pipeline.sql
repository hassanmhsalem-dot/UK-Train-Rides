-- full_railway_pipeline.sql
-- UK National Rail End-to-End SQL Pipeline (Microsoft SQL Server T-SQL)

-- Staging
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
-- BULK INSERT stg_railway_raw
-- FROM 'D:\كتب\DEPI_R5_EL_FAYOUM_JDA\Capston_Project\railway.csv'
-- WITH (
--     FIRSTROW = 2,
--     FIELDTERMINATOR = ',',
--     ROWTERMINATOR = '\n',
--     KEEPNULLS,
--     TABLOCK
-- );

-- Staging verification: Confirm total row count (Expected: 31,653)
SELECT 
    COUNT(*) AS stg_row_count,
    CASE WHEN COUNT(*) = 31653 THEN 'PASSED' ELSE 'FAILED' END AS load_status
FROM stg_railway_raw;

-- Cleaning
DROP TABLE IF EXISTS clean_railway_journeys;

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
    -- Lead time in days between purchase and departure
    DATEDIFF(DAY, CAST(date_of_purchase AS DATE), CAST(date_of_journey AS DATE)) AS lead_time_days,
    -- Scheduled trip duration handling overnight arrivals crossing midnight
    CASE 
        WHEN CAST(arrival_time AS TIME) >= CAST(departure_time AS TIME) THEN
            DATEDIFF(MINUTE, CAST(departure_time AS TIME), CAST(arrival_time AS TIME))
        ELSE
            DATEDIFF(MINUTE, CAST(departure_time AS TIME), CAST(arrival_time AS TIME)) + 1440
    END AS scheduled_duration_minutes,
    -- Delay minutes handling overnight actual arrivals crossing midnight
    CASE 
        WHEN UPPER(LTRIM(RTRIM(journey_status))) = 'CANCELLED' THEN NULL
        WHEN actual_arrival_time IS NULL OR LTRIM(RTRIM(actual_arrival_time)) = '' THEN NULL
        WHEN TRY_CAST(actual_arrival_time AS TIME) IS NULL THEN NULL
        WHEN TRY_CAST(actual_arrival_time AS TIME) >= CAST(arrival_time AS TIME) THEN
            DATEDIFF(MINUTE, CAST(arrival_time AS TIME), TRY_CAST(actual_arrival_time AS TIME))
        ELSE
            DATEDIFF(MINUTE, CAST(arrival_time AS TIME), TRY_CAST(actual_arrival_time AS TIME)) + 1440
    END AS delay_minutes,
    -- Unified corridor route
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

-- Cleaning Check 1: Row count preservation (Expected: 31,653)
SELECT 
    COUNT(*) AS clean_row_count,
    CASE WHEN COUNT(*) = 31653 THEN 'PASSED' ELSE 'FAILED' END AS check_status
FROM clean_railway_journeys;

-- Cleaning Check 2: Null and constraint validity checks
SELECT
    SUM(CASE WHEN transaction_id IS NULL THEN 1 ELSE 0 END) AS null_ids,
    SUM(CASE WHEN railcard IS NULL THEN 1 ELSE 0 END) AS null_railcards,
    SUM(CASE WHEN reason_for_delay IS NULL THEN 1 ELSE 0 END) AS null_reasons,
    SUM(CASE WHEN price IS NULL OR price <= 0 THEN 1 ELSE 0 END) AS invalid_prices,
    SUM(CASE WHEN lead_time_days IS NULL OR lead_time_days < 0 THEN 1 ELSE 0 END) AS invalid_lead_times
FROM clean_railway_journeys;

-- Cleaning Check 3: Standardized delay reasons (Expected: 6 categories)
SELECT 
    reason_for_delay,
    COUNT(*) AS count
FROM clean_railway_journeys
GROUP BY reason_for_delay
ORDER BY count DESC;

-- Cleaning Check 4: Cancelled trips consistency
SELECT 
    journey_status,
    COUNT(*) AS total,
    SUM(CASE WHEN actual_arrival_time IS NULL THEN 1 ELSE 0 END) AS null_actual_arrivals
FROM clean_railway_journeys
GROUP BY journey_status;

-- Cleaning Check 5: Station standardization check (Expected: 0 unmapped)
SELECT 
    COUNT(*) AS unmapped_edinburgh,
    CASE WHEN COUNT(*) = 0 THEN 'PASSED' ELSE 'FAILED' END AS check_status
FROM clean_railway_journeys
WHERE UPPER(LTRIM(RTRIM(arrival_destination))) = 'EDINBURGH';

-- Star Schema
DROP TABLE IF EXISTS fact_journeys;
DROP TABLE IF EXISTS dim_journey_status;
DROP TABLE IF EXISTS dim_ticket_payment;
DROP TABLE IF EXISTS dim_station;
DROP TABLE IF EXISTS dim_date;

CREATE TABLE dim_date (
    date_key INT NOT NULL,
    full_date DATE NOT NULL,
    year_num INT NOT NULL,
    quarter_num INT NOT NULL,
    quarter_name VARCHAR(10) NOT NULL,
    month_num INT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    month_year VARCHAR(20) NOT NULL,
    day_num INT NOT NULL,
    day_name VARCHAR(20) NOT NULL,
    day_of_week INT NOT NULL,
    is_weekend INT NOT NULL,
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT uq_dim_date_full UNIQUE (full_date),
    CONSTRAINT chk_dim_date_weekend CHECK (is_weekend IN (0, 1))
);

WITH date_series AS (
    SELECT CAST('2023-12-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d)
    FROM date_series
    WHERE d < '2024-05-31'
)
INSERT INTO dim_date (
    date_key,
    full_date,
    year_num,
    quarter_num,
    quarter_name,
    month_num,
    month_name,
    month_year,
    day_num,
    day_name,
    day_of_week,
    is_weekend
)
SELECT
    (YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d)) AS date_key,
    d AS full_date,
    YEAR(d) AS year_num,
    DATEPART(QUARTER, d) AS quarter_num,
    CONCAT('Q', DATEPART(QUARTER, d)) AS quarter_name,
    MONTH(d) AS month_num,
    DATENAME(MONTH, d) AS month_name,
    CONCAT(YEAR(d), '-', RIGHT(CONCAT('0', MONTH(d)), 2)) AS month_year,
    DAY(d) AS day_num,
    DATENAME(WEEKDAY, d) AS day_name,
    DATEPART(WEEKDAY, d) AS day_of_week,
    CASE 
        WHEN DATENAME(WEEKDAY, d) IN ('Saturday', 'Sunday') THEN 1 
        ELSE 0 
    END AS is_weekend
FROM date_series
OPTION (MAXRECURSION 500);

CREATE TABLE dim_station (
    station_key INT IDENTITY(1, 1) NOT NULL,
    station_name VARCHAR(100) NOT NULL,
    is_hub_station INT NOT NULL,
    CONSTRAINT pk_dim_station PRIMARY KEY (station_key),
    CONSTRAINT uq_dim_station_name UNIQUE (station_name),
    CONSTRAINT chk_dim_station_hub CHECK (is_hub_station IN (0, 1)),
    CONSTRAINT df_dim_station_hub DEFAULT (0) FOR is_hub_station
);

-- Populate dim_station with curated hub stations handling >= 4,000 total journeys
INSERT INTO dim_station (station_name, is_hub_station)
SELECT 
    s.station_name,
    -- Curated hub stations representing primary UK metropolitan interchanges and London rail termini
    -- each handling >= 4,000 total journeys (departures + arrivals):
    -- Birmingham New Street (9,878), Manchester Piccadilly (9,618), Liverpool Lime Street (9,583),
    -- London Euston (6,521), York (4,946), London Paddington (4,851),
    -- London St Pancras (4,640), Reading (4,514), London Kings Cross (4,313).
    CASE 
        WHEN s.station_name IN (
            'Birmingham New Street',
            'Liverpool Lime Street',
            'London Euston',
            'London Kings Cross',
            'London Paddington',
            'London St Pancras',
            'Manchester Piccadilly',
            'Reading',
            'York'
        ) THEN 1 
        ELSE 0 
    END AS is_hub_station
FROM (
    SELECT departure_station AS station_name FROM clean_railway_journeys
    UNION
    SELECT arrival_destination AS station_name FROM clean_railway_journeys
) s
ORDER BY s.station_name;

CREATE TABLE dim_ticket_payment (
    ticket_payment_key INT IDENTITY(1, 1) NOT NULL,
    purchase_type VARCHAR(20) NOT NULL,
    payment_method VARCHAR(30) NOT NULL,
    railcard VARCHAR(20) NOT NULL,
    ticket_class VARCHAR(20) NOT NULL,
    ticket_type VARCHAR(20) NOT NULL,
    CONSTRAINT pk_dim_ticket_payment PRIMARY KEY (ticket_payment_key),
    CONSTRAINT uq_ticket_payment UNIQUE (purchase_type, payment_method, railcard, ticket_class, ticket_type)
);

INSERT INTO dim_ticket_payment (purchase_type, payment_method, railcard, ticket_class, ticket_type)
SELECT DISTINCT
    purchase_type,
    payment_method,
    railcard,
    ticket_class,
    ticket_type
FROM clean_railway_journeys
ORDER BY purchase_type, payment_method, railcard, ticket_class, ticket_type;

CREATE TABLE dim_journey_status (
    journey_status_key INT IDENTITY(1, 1) NOT NULL,
    journey_status VARCHAR(20) NOT NULL,
    reason_for_delay VARCHAR(100) NOT NULL,
    refund_request VARCHAR(10) NOT NULL,
    CONSTRAINT pk_dim_journey_status PRIMARY KEY (journey_status_key),
    CONSTRAINT uq_journey_status UNIQUE (journey_status, reason_for_delay, refund_request)
);

INSERT INTO dim_journey_status (journey_status, reason_for_delay, refund_request)
SELECT DISTINCT
    journey_status,
    reason_for_delay,
    refund_request
FROM clean_railway_journeys
ORDER BY journey_status, reason_for_delay, refund_request;

CREATE TABLE fact_journeys (
    journey_key INT IDENTITY(1, 1) NOT NULL,
    transaction_id VARCHAR(50) NOT NULL,
    purchase_date_key INT NOT NULL,
    journey_date_key INT NOT NULL,
    departure_station_key INT NOT NULL,
    arrival_station_key INT NOT NULL,
    ticket_payment_key INT NOT NULL,
    journey_status_key INT NOT NULL,
    departure_time TIME(0) NOT NULL,
    arrival_time TIME(0) NOT NULL,
    actual_arrival_time TIME(0) NULL,
    price DECIMAL(10, 2) NOT NULL,
    lead_time_days INT NOT NULL,
    scheduled_duration_minutes INT NOT NULL,
    delay_minutes INT NULL,
    is_delayed INT NOT NULL,
    is_cancelled INT NOT NULL,
    is_refunded INT NOT NULL,
    CONSTRAINT pk_fact_journeys PRIMARY KEY (journey_key),
    CONSTRAINT uq_fact_transaction_id UNIQUE (transaction_id),
    CONSTRAINT fk_fact_purchase_date FOREIGN KEY (purchase_date_key) REFERENCES dim_date(date_key),
    CONSTRAINT fk_fact_journey_date FOREIGN KEY (journey_date_key) REFERENCES dim_date(date_key),
    CONSTRAINT fk_fact_departure_station FOREIGN KEY (departure_station_key) REFERENCES dim_station(station_key),
    CONSTRAINT fk_fact_arrival_station FOREIGN KEY (arrival_station_key) REFERENCES dim_station(station_key),
    CONSTRAINT fk_fact_ticket_payment FOREIGN KEY (ticket_payment_key) REFERENCES dim_ticket_payment(ticket_payment_key),
    CONSTRAINT fk_fact_journey_status FOREIGN KEY (journey_status_key) REFERENCES dim_journey_status(journey_status_key),
    CONSTRAINT chk_fact_price CHECK (price >= 0),
    CONSTRAINT chk_fact_is_delayed CHECK (is_delayed IN (0, 1)),
    CONSTRAINT chk_fact_is_cancelled CHECK (is_cancelled IN (0, 1)),
    CONSTRAINT chk_fact_is_refunded CHECK (is_refunded IN (0, 1))
);

INSERT INTO fact_journeys (
    transaction_id,
    purchase_date_key,
    journey_date_key,
    departure_station_key,
    arrival_station_key,
    ticket_payment_key,
    journey_status_key,
    departure_time,
    arrival_time,
    actual_arrival_time,
    price,
    lead_time_days,
    scheduled_duration_minutes,
    delay_minutes,
    is_delayed,
    is_cancelled,
    is_refunded
)
SELECT
    c.transaction_id,
    (YEAR(c.date_of_purchase) * 10000 + MONTH(c.date_of_purchase) * 100 + DAY(c.date_of_purchase)) AS purchase_date_key,
    (YEAR(c.date_of_journey) * 10000 + MONTH(c.date_of_journey) * 100 + DAY(c.date_of_journey)) AS journey_date_key,
    dep.station_key AS departure_station_key,
    arr.station_key AS arrival_station_key,
    tp.ticket_payment_key,
    js.journey_status_key,
    c.departure_time,
    c.arrival_time,
    c.actual_arrival_time,
    c.price,
    c.lead_time_days,
    c.scheduled_duration_minutes,
    c.delay_minutes,
    CASE WHEN UPPER(LTRIM(RTRIM(c.journey_status))) = 'DELAYED' THEN 1 ELSE 0 END AS is_delayed,
    CASE WHEN UPPER(LTRIM(RTRIM(c.journey_status))) = 'CANCELLED' THEN 1 ELSE 0 END AS is_cancelled,
    CASE WHEN UPPER(LTRIM(RTRIM(c.refund_request))) = 'YES' THEN 1 ELSE 0 END AS is_refunded
FROM clean_railway_journeys c
INNER JOIN dim_station dep ON c.departure_station = dep.station_name
INNER JOIN dim_station arr ON c.arrival_destination = arr.station_name
INNER JOIN dim_ticket_payment tp 
    ON c.purchase_type = tp.purchase_type 
   AND c.payment_method = tp.payment_method 
   AND c.railcard = tp.railcard 
   AND c.ticket_class = tp.ticket_class 
   AND c.ticket_type = tp.ticket_type
INNER JOIN dim_journey_status js 
    ON c.journey_status = js.journey_status 
   AND c.reason_for_delay = js.reason_for_delay 
   AND c.refund_request = js.refund_request;

-- Star schema row count check
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL
SELECT 'dim_station', COUNT(*) FROM dim_station
UNION ALL
SELECT 'dim_ticket_payment', COUNT(*) FROM dim_ticket_payment
UNION ALL
SELECT 'dim_journey_status', COUNT(*) FROM dim_journey_status
UNION ALL
SELECT 'fact_journeys', COUNT(*) FROM fact_journeys;

-- Star schema measure integrity check
SELECT 
    COUNT(*) AS total_fact_rows,
    SUM(price) AS total_fact_revenue,
    CASE 
        WHEN COUNT(*) = 31653 AND SUM(price) > 0 THEN 'PASSED' 
        ELSE 'FAILED' 
    END AS dwh_status
FROM fact_journeys;

-- Analytics

-- Query 1A: Commercial performance by ticket class and ticket type
WITH product_summary AS (
    SELECT
        tp.ticket_class,
        tp.ticket_type,
        COUNT(f.journey_key) AS ticket_volume,
        SUM(f.price) AS total_revenue,
        ROUND(AVG(f.price), 2) AS avg_ticket_price
    FROM fact_journeys f
    INNER JOIN dim_ticket_payment tp ON f.ticket_payment_key = tp.ticket_payment_key
    GROUP BY tp.ticket_class, tp.ticket_type
)
SELECT
    ticket_class,
    ticket_type,
    ticket_volume,
    ROUND(100.0 * ticket_volume / SUM(ticket_volume) OVER (), 2) AS volume_share_pct,
    total_revenue,
    ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 2) AS revenue_share_pct,
    avg_ticket_price,
    DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
FROM product_summary
ORDER BY total_revenue DESC;

-- Query 1B: Channel performance by purchase type and payment method
WITH channel_summary AS (
    SELECT
        tp.purchase_type,
        tp.payment_method,
        COUNT(f.journey_key) AS ticket_volume,
        SUM(f.price) AS total_revenue,
        ROUND(AVG(f.price), 2) AS avg_ticket_price
    FROM fact_journeys f
    INNER JOIN dim_ticket_payment tp ON f.ticket_payment_key = tp.ticket_payment_key
    GROUP BY tp.purchase_type, tp.payment_method
)
SELECT
    purchase_type,
    payment_method,
    ticket_volume,
    ROUND(100.0 * ticket_volume / SUM(ticket_volume) OVER (), 2) AS volume_share_pct,
    total_revenue,
    ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 2) AS revenue_share_pct,
    avg_ticket_price,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS channel_revenue_rank
FROM channel_summary
ORDER BY total_revenue DESC;

-- Query 1C: Railcard discount penetration
WITH railcard_summary AS (
    SELECT
        tp.railcard,
        COUNT(f.journey_key) AS ticket_volume,
        SUM(f.price) AS total_revenue,
        ROUND(AVG(f.price), 2) AS avg_ticket_price
    FROM fact_journeys f
    INNER JOIN dim_ticket_payment tp ON f.ticket_payment_key = tp.ticket_payment_key
    GROUP BY tp.railcard
)
SELECT
    railcard,
    ticket_volume,
    ROUND(100.0 * ticket_volume / SUM(ticket_volume) OVER (), 2) AS volume_share_pct,
    total_revenue,
    ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 2) AS revenue_share_pct,
    avg_ticket_price,
    RANK() OVER (ORDER BY ticket_volume DESC) AS adoption_rank
FROM railcard_summary
ORDER BY ticket_volume DESC;

-- Query 2A: Network-wide reliability KPIs
WITH network_reliability AS (
    SELECT
        COUNT(*) AS total_journeys,
        SUM(CASE WHEN js.journey_status = 'On Time' THEN 1 ELSE 0 END) AS on_time_journeys,
        SUM(f.is_delayed) AS delayed_journeys,
        SUM(f.is_cancelled) AS cancelled_journeys,
        SUM(f.delay_minutes) AS total_delay_minutes
    FROM fact_journeys f
    INNER JOIN dim_journey_status js ON f.journey_status_key = js.journey_status_key
)
SELECT
    total_journeys,
    on_time_journeys,
    ROUND(100.0 * on_time_journeys / total_journeys, 2) AS on_time_rate_pct,
    delayed_journeys,
    ROUND(100.0 * delayed_journeys / total_journeys, 2) AS delay_rate_pct,
    cancelled_journeys,
    ROUND(100.0 * cancelled_journeys / total_journeys, 2) AS cancellation_rate_pct,
    total_delay_minutes,
    ROUND(1.0 * total_delay_minutes / NULLIF(delayed_journeys, 0), 2) AS avg_delay_minutes_per_delayed_trip
FROM network_reliability;

-- Query 2B: Root-cause disruption ranking
WITH disruption_analysis AS (
    SELECT
        js.reason_for_delay,
        COUNT(f.journey_key) AS total_disruptions,
        SUM(f.is_delayed) AS delayed_trips,
        SUM(f.is_cancelled) AS cancelled_trips,
        COALESCE(SUM(f.delay_minutes), 0) AS total_delay_minutes,
        ROUND(AVG(CASE WHEN f.is_delayed = 1 THEN CAST(f.delay_minutes AS FLOAT) END), 2) AS avg_delay_minutes
    FROM fact_journeys f
    INNER JOIN dim_journey_status js ON f.journey_status_key = js.journey_status_key
    WHERE js.journey_status IN ('Delayed', 'Cancelled')
    GROUP BY js.reason_for_delay
)
SELECT
    reason_for_delay,
    total_disruptions,
    ROUND(100.0 * total_disruptions / SUM(total_disruptions) OVER (), 2) AS disruption_share_pct,
    delayed_trips,
    cancelled_trips,
    total_delay_minutes,
    avg_delay_minutes,
    RANK() OVER (ORDER BY total_disruptions DESC) AS rank_by_disruption_frequency
FROM disruption_analysis
ORDER BY total_disruptions DESC;

-- Query 3A: Top 10 corridors by volume
WITH route_volume AS (
    SELECT
        dep.station_name AS departure_station,
        arr.station_name AS arrival_destination,
        CONCAT(dep.station_name, ' -> ', arr.station_name) AS corridor_route,
        COUNT(f.journey_key) AS total_journeys,
        SUM(f.price) AS total_revenue,
        ROUND(AVG(f.price), 2) AS avg_ticket_price,
        ROUND(100.0 * SUM(f.is_delayed) / COUNT(f.journey_key), 2) AS delay_rate_pct,
        ROUND(100.0 * SUM(f.is_cancelled) / COUNT(f.journey_key), 2) AS cancellation_rate_pct,
        ROUND(AVG(CASE WHEN f.is_delayed = 1 THEN CAST(f.delay_minutes AS FLOAT) END), 2) AS avg_delay_when_delayed
    FROM fact_journeys f
    INNER JOIN dim_station dep ON f.departure_station_key = dep.station_key
    INNER JOIN dim_station arr ON f.arrival_station_key = arr.station_key
    GROUP BY dep.station_name, arr.station_name
)
SELECT TOP (10)
    corridor_route,
    total_journeys,
    ROW_NUMBER() OVER (ORDER BY total_journeys DESC) AS volume_rank,
    total_revenue,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
    avg_ticket_price,
    delay_rate_pct,
    cancellation_rate_pct,
    avg_delay_when_delayed
FROM route_volume
ORDER BY total_journeys DESC;

-- Query 3B: Top 10 corridors by revenue
WITH route_revenue AS (
    SELECT
        CONCAT(dep.station_name, ' -> ', arr.station_name) AS corridor_route,
        COUNT(f.journey_key) AS total_journeys,
        SUM(f.price) AS total_revenue,
        ROUND(AVG(f.price), 2) AS avg_ticket_price,
        ROUND(100.0 * SUM(f.is_delayed) / COUNT(f.journey_key), 2) AS delay_rate_pct,
        ROUND(100.0 * SUM(f.is_cancelled) / COUNT(f.journey_key), 2) AS cancellation_rate_pct
    FROM fact_journeys f
    INNER JOIN dim_station dep ON f.departure_station_key = dep.station_key
    INNER JOIN dim_station arr ON f.arrival_station_key = arr.station_key
    GROUP BY dep.station_name, arr.station_name
)
SELECT TOP (10)
    corridor_route,
    total_revenue,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
    total_journeys,
    ROW_NUMBER() OVER (ORDER BY total_journeys DESC) AS volume_rank,
    ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 2) AS network_revenue_share_pct,
    avg_ticket_price,
    delay_rate_pct,
    cancellation_rate_pct
FROM route_revenue
ORDER BY total_revenue DESC;

-- Query 3C: Departure station performance matrix
WITH hub_performance AS (
    SELECT
        dep.station_name AS station_name,
        dep.is_hub_station,
        COUNT(f.journey_key) AS total_departures,
        SUM(f.price) AS total_revenue,
        ROUND(100.0 * SUM(CASE WHEN f.is_delayed = 0 AND f.is_cancelled = 0 THEN 1 ELSE 0 END) / COUNT(f.journey_key), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(f.is_delayed) / COUNT(f.journey_key), 2) AS delay_rate_pct,
        ROUND(100.0 * SUM(f.is_cancelled) / COUNT(f.journey_key), 2) AS cancellation_rate_pct,
        COALESCE(SUM(f.delay_minutes), 0) AS total_delay_minutes
    FROM fact_journeys f
    INNER JOIN dim_station dep ON f.departure_station_key = dep.station_key
    GROUP BY dep.station_name, dep.is_hub_station
)
SELECT
    station_name,
    CASE WHEN is_hub_station = 1 THEN 'Yes' ELSE 'No' END AS is_hub_station,
    total_departures,
    total_revenue,
    on_time_rate_pct,
    delay_rate_pct,
    cancellation_rate_pct,
    total_delay_minutes,
    DENSE_RANK() OVER (ORDER BY on_time_rate_pct DESC) AS punctuality_rank,
    ROW_NUMBER() OVER (ORDER BY total_departures DESC) AS volume_rank
FROM hub_performance
ORDER BY total_departures DESC;

-- Query 4A: Refund requests by status
WITH status_refunds AS (
    SELECT
        js.journey_status,
        COUNT(f.journey_key) AS total_journeys,
        SUM(f.is_refunded) AS refund_requests,
        ROUND(100.0 * SUM(f.is_refunded) / COUNT(f.journey_key), 2) AS refund_request_rate_pct,
        SUM(f.price) AS total_ticket_value,
        SUM(CASE WHEN f.is_refunded = 1 THEN f.price ELSE 0 END) AS refunded_revenue,
        SUM(CASE WHEN f.is_refunded = 0 THEN f.price ELSE 0 END) AS net_retained_revenue
    FROM fact_journeys f
    INNER JOIN dim_journey_status js ON f.journey_status_key = js.journey_status_key
    GROUP BY js.journey_status
)
SELECT
    journey_status,
    total_journeys,
    refund_requests,
    refund_request_rate_pct,
    total_ticket_value,
    refunded_revenue,
    net_retained_revenue,
    ROUND(100.0 * refunded_revenue / NULLIF(total_ticket_value, 0), 2) AS revenue_lost_pct
FROM status_refunds
ORDER BY refund_requests DESC;

-- Query 4B: Refund liability by delay reason
WITH delay_reason_refunds AS (
    SELECT
        js.reason_for_delay,
        COUNT(f.journey_key) AS impacted_journeys,
        SUM(f.is_refunded) AS refund_requests,
        ROUND(100.0 * SUM(f.is_refunded) / COUNT(f.journey_key), 2) AS refund_claim_rate_pct,
        SUM(CASE WHEN f.is_refunded = 1 THEN f.price ELSE 0 END) AS total_refunded_amount
    FROM fact_journeys f
    INNER JOIN dim_journey_status js ON f.journey_status_key = js.journey_status_key
    WHERE js.journey_status IN ('Delayed', 'Cancelled')
    GROUP BY js.reason_for_delay
)
SELECT
    reason_for_delay,
    impacted_journeys,
    refund_requests,
    refund_claim_rate_pct,
    total_refunded_amount,
    ROUND(100.0 * total_refunded_amount / SUM(total_refunded_amount) OVER (), 2) AS refund_cost_share_pct,
    RANK() OVER (ORDER BY total_refunded_amount DESC) AS financial_impact_rank
FROM delay_reason_refunds
ORDER BY total_refunded_amount DESC;

-- Query 5A: Monthly volume and revenue growth (MoM via LAG)
WITH monthly_journey_metrics AS (
    SELECT
        d.year_num,
        d.month_num,
        d.month_name,
        d.month_year,
        COUNT(f.journey_key) AS journey_count,
        SUM(f.price) AS total_revenue,
        ROUND(AVG(f.price), 2) AS avg_ticket_price
    FROM fact_journeys f
    INNER JOIN dim_date d ON f.journey_date_key = d.date_key
    GROUP BY d.year_num, d.month_num, d.month_name, d.month_year
)
SELECT
    month_year,
    month_name,
    journey_count,
    LAG(journey_count) OVER (ORDER BY year_num, month_num) AS prev_month_journeys,
    ROUND(100.0 * (journey_count - LAG(journey_count) OVER (ORDER BY year_num, month_num)) / 
          NULLIF(LAG(journey_count) OVER (ORDER BY year_num, month_num), 0), 2) AS mom_volume_growth_pct,
    total_revenue,
    LAG(total_revenue) OVER (ORDER BY year_num, month_num) AS prev_month_revenue,
    ROUND(100.0 * (total_revenue - LAG(total_revenue) OVER (ORDER BY year_num, month_num)) / 
          NULLIF(LAG(total_revenue) OVER (ORDER BY year_num, month_num), 0), 2) AS mom_revenue_growth_pct,
    avg_ticket_price
FROM monthly_journey_metrics
ORDER BY year_num, month_num;

-- Query 5B: Monthly operational reliability trend
WITH monthly_service_metrics AS (
    SELECT
        d.year_num,
        d.month_num,
        d.month_year,
        COUNT(f.journey_key) AS journey_count,
        ROUND(100.0 * SUM(CASE WHEN f.is_delayed = 0 AND f.is_cancelled = 0 THEN 1 ELSE 0 END) / COUNT(f.journey_key), 2) AS on_time_rate_pct,
        ROUND(100.0 * SUM(f.is_delayed) / COUNT(f.journey_key), 2) AS delay_rate_pct,
        ROUND(100.0 * SUM(f.is_cancelled) / COUNT(f.journey_key), 2) AS cancellation_rate_pct,
        ROUND(100.0 * SUM(f.is_refunded) / COUNT(f.journey_key), 2) AS refund_rate_pct,
        COALESCE(SUM(f.delay_minutes), 0) AS total_delay_minutes
    FROM fact_journeys f
    INNER JOIN dim_date d ON f.journey_date_key = d.date_key
    GROUP BY d.year_num, d.month_num, d.month_year
)
SELECT
    month_year,
    journey_count,
    on_time_rate_pct,
    delay_rate_pct,
    cancellation_rate_pct,
    refund_rate_pct,
    total_delay_minutes,
    ROUND(1.0 * total_delay_minutes / NULLIF(journey_count, 0), 2) AS avg_delay_minutes_per_scheduled_trip
FROM monthly_service_metrics
ORDER BY year_num, month_num;
