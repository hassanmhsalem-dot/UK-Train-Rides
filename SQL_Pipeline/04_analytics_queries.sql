-- 04_analytics_queries.sql
-- UK National Rail Project: Business Analytics, Aggregations & Window Functions (T-SQL)

-- SECTION 1: REVENUE AND TICKET VOLUME ANALYSIS

-- Query 1A: Commercial Performance by Ticket Class and Ticket Type
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

-- Query 1B: Channel Performance by Purchase Type and Payment Method
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

-- Query 1C: Railcard Penetration and Discount Distribution
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

-- SECTION 2: SERVICE RELIABILITY, DELAYS AND CANCELLATIONS

-- Query 2A: Network-Wide Service Reliability and Punctuality KPIs
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

-- Query 2B: Root-Cause Disruption Breakdown and Severity Ranking
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

-- SECTION 3: ROUTE CORRIDOR PERFORMANCE AND STATION METRICS

-- Query 3A: Top 10 Busiest Route Corridors by Passenger Volume
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

-- Query 3B: Top 10 Highest-Yield Route Corridors by Total Revenue
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

-- Query 3C: Departure Station Performance Matrix and Punctuality Ranking
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

-- SECTION 4: REFUND REQUESTS AND FINANCIAL REVENUE EXPOSURE

-- Query 4A: Refund Request Rates and Revenue Impact by Journey Status
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

-- Query 4B: Refund Liability by Disruption Reason
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

-- SECTION 5: MONTHLY TRENDS AND PERIOD-OVER-PERIOD PERFORMANCE

-- Query 5A: Monthly Journey Volume and Revenue Evolution (Month-over-Month Growth via LAG)
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

-- Query 5B: Monthly Operational Reliability and Service Quality Trend
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
