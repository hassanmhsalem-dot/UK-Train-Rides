-- 03_star_schema_dwh.sql
-- UK National Rail Project: Star Schema Data Warehouse DDL & Population (T-SQL)

-- Drop fact and dimension tables in foreign key dependency order
DROP TABLE IF EXISTS fact_journeys;
DROP TABLE IF EXISTS dim_journey_status;
DROP TABLE IF EXISTS dim_ticket_payment;
DROP TABLE IF EXISTS dim_station;
DROP TABLE IF EXISTS dim_date;

-- 1. Dimension Table: dim_date (Date Dimension)
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

-- Populate dim_date using T-SQL recursive CTE covering Dec 2023 - May 2024
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

-- 2. Dimension Table: dim_station (Unified Station Dimension)
CREATE TABLE dim_station (
    station_key INT IDENTITY(1, 1) NOT NULL,
    station_name VARCHAR(100) NOT NULL,
    is_hub_station INT NOT NULL CONSTRAINT df_dim_station_hub DEFAULT (0),
    CONSTRAINT pk_dim_station PRIMARY KEY (station_key),
    CONSTRAINT uq_dim_station_name UNIQUE (station_name),
    CONSTRAINT chk_dim_station_hub CHECK (is_hub_station IN (0, 1))
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

-- 3. Dimension Table: dim_ticket_payment (Ticketing & Payment Dimension)
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

-- Populate dim_ticket_payment with distinct commercial combinations
INSERT INTO dim_ticket_payment (purchase_type, payment_method, railcard, ticket_class, ticket_type)
SELECT DISTINCT
    purchase_type,
    payment_method,
    railcard,
    ticket_class,
    ticket_type
FROM clean_railway_journeys
ORDER BY purchase_type, payment_method, railcard, ticket_class, ticket_type;

-- 4. Dimension Table: dim_journey_status (Operational Status & Disruption Dimension)
CREATE TABLE dim_journey_status (
    journey_status_key INT IDENTITY(1, 1) NOT NULL,
    journey_status VARCHAR(20) NOT NULL,
    reason_for_delay VARCHAR(100) NOT NULL,
    refund_request VARCHAR(10) NOT NULL,
    CONSTRAINT pk_dim_journey_status PRIMARY KEY (journey_status_key),
    CONSTRAINT uq_journey_status UNIQUE (journey_status, reason_for_delay, refund_request)
);

-- Populate dim_journey_status with distinct operational status combinations
INSERT INTO dim_journey_status (journey_status, reason_for_delay, refund_request)
SELECT DISTINCT
    journey_status,
    reason_for_delay,
    refund_request
FROM clean_railway_journeys
ORDER BY journey_status, reason_for_delay, refund_request;

-- 5. Fact Table: fact_journeys (Grain: One Row per Ticket Transaction)
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

-- Populate fact_journeys using explicit INNER JOIN operations
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

-- Dimensional Model Verification Check 1: Record counts across all tables
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL
SELECT 'dim_station', COUNT(*) FROM dim_station
UNION ALL
SELECT 'dim_ticket_payment', COUNT(*) FROM dim_ticket_payment
UNION ALL
SELECT 'dim_journey_status', COUNT(*) FROM dim_journey_status
UNION ALL
SELECT 'fact_journeys', COUNT(*) FROM fact_journeys;

-- Dimensional Model Verification Check 2: Measure integrity check with flexible decimal validation
SELECT 
    COUNT(*) AS total_fact_rows,
    SUM(price) AS total_fact_revenue,
    SUM(is_delayed) AS total_delayed_trips,
    SUM(is_cancelled) AS total_cancelled_trips,
    SUM(is_refunded) AS total_refunded_trips,
    CASE 
        WHEN COUNT(*) = 31653 AND SUM(price) > 0 THEN 'PASSED' 
        ELSE 'FAILED' 
    END AS model_integrity_check
FROM fact_journeys;