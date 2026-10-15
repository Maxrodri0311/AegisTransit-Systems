-- ==============================================================================
-- AegisTransit Telecom Lakehouse - Continuous Rollups & 95th Percentile Burst Window
-- Target: PostgreSQL 16 Enterprise
-- Calculates Monthly 95th Percentile Burstable Billing vs CIR Baseline
-- ==============================================================================

SET search_path TO telecom_lakehouse, public;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_monthly_circuit_billing_rollup AS
WITH monthly_samples AS (
    SELECT 
        DATE_TRUNC('month', t.event_timestamp) AS billing_month,
        t.circuit_id,
        t.carrier_name,
        c.pop_location,
        c.committed_information_rate_mbps AS cir_mbps,
        c.peak_information_rate_mbps AS pir_mbps,
        c.base_cost_usd_month AS base_mrc_usd,
        c.burst_cost_per_mbps_usd,
        COUNT(t.telemetry_id) AS total_samples_count,
        ROUND(AVG(t.aggregate_mbps), 2) AS mean_bandwidth_mbps,
        ROUND(MAX(t.aggregate_mbps), 2) AS peak_bandwidth_mbps,
        ROUND(
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY t.aggregate_mbps)::NUMERIC, 
            2
        ) AS effective_95th_mbps
    FROM traffic_telemetry t
    JOIN circuits_catalog c ON t.circuit_id = c.circuit_id
    GROUP BY 
        DATE_TRUNC('month', t.event_timestamp),
        t.circuit_id,
        t.carrier_name,
        c.pop_location,
        c.committed_information_rate_mbps,
        c.peak_information_rate_mbps,
        c.base_cost_usd_month,
        c.burst_cost_per_mbps_usd
),
billing_calculations AS (
    SELECT 
        billing_month,
        circuit_id,
        carrier_name,
        pop_location,
        cir_mbps,
        pir_mbps,
        effective_95th_mbps,
        base_mrc_usd,
        burst_cost_per_mbps_usd,
        GREATEST(0.0, effective_95th_mbps - cir_mbps) AS burst_overage_mbps,
        CASE 
            WHEN effective_95th_mbps > cir_mbps THEN TRUE 
            ELSE FALSE 
        END AS is_bursting,
        ROUND(
            base_mrc_usd + (GREATEST(0.0, effective_95th_mbps - cir_mbps) * burst_cost_per_mbps_usd),
            2
        ) AS total_billed_amount_usd
    FROM monthly_samples
)
SELECT 
    billing_month,
    circuit_id,
    carrier_name,
    pop_location,
    cir_mbps,
    effective_95th_mbps,
    burst_overage_mbps,
    is_bursting,
    base_mrc_usd,
    total_billed_amount_usd,
    ROUND(
        (burst_overage_mbps * burst_cost_per_mbps_usd),
        2
    ) AS burst_penalty_usd,
    ROUND(
        total_billed_amount_usd / NULLIF(effective_95th_mbps, 0),
        4
    ) AS effective_cost_per_mbps_usd
FROM billing_calculations
ORDER BY billing_month DESC, total_billed_amount_usd DESC;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_circuit_billing_month_id
    ON mv_monthly_circuit_billing_rollup (billing_month, circuit_id);