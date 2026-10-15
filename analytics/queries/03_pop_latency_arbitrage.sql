-- ==============================================================================
-- AegisTransit Telemetry Lakehouse - PoP Latency Arbitrage & SLA Optimization
-- Target: PostgreSQL 16 Enterprise
-- Calculates regional PoP transit efficiency, latency variance, and cost trade-offs
-- ==============================================================================

SET search_path TO telecom_lakehouse, public;

CREATE OR REPLACE VIEW v_pop_latency_cost_arbitrage AS
WITH pop_traffic_aggregates AS (
    SELECT 
        c.pop_location,
        c.circuit_id,
        c.carrier_name,
        c.committed_information_rate_mbps AS cir_mbps,
        c.peak_information_rate_mbps AS pir_mbps,
        c.latency_sla_ms,
        c.burst_cost_per_mbps_usd,
        c.base_cost_usd_month,
        COUNT(t.telemetry_id) AS total_intervals_analyzed,
        ROUND(AVG(t.aggregate_mbps), 2) AS avg_throughput_mbps,
        ROUND(MAX(t.aggregate_mbps), 2) AS peak_throughput_mbps,
        ROUND(
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY t.aggregate_mbps)::NUMERIC, 
            2
        ) AS p95_throughput_mbps,
        ROUND(
            PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY t.aggregate_mbps)::NUMERIC, 
            2
        ) AS p99_throughput_mbps
    FROM circuits_catalog c
    LEFT JOIN traffic_telemetry t ON c.circuit_id = t.circuit_id
    GROUP BY 
        c.pop_location,
        c.circuit_id,
        c.carrier_name,
        c.committed_information_rate_mbps,
        c.peak_information_rate_mbps,
        c.latency_sla_ms,
        c.burst_cost_per_mbps_usd,
        c.base_cost_usd_month
),
regional_benchmarks AS (
    SELECT 
        pop_location,
        circuit_id,
        carrier_name,
        cir_mbps,
        p95_throughput_mbps,
        latency_sla_ms,
        burst_cost_per_mbps_usd,
        base_cost_usd_month,
        -- Regional baseline comparison window functions
        ROUND(AVG(latency_sla_ms) OVER(PARTITION BY pop_location), 2) AS pop_avg_latency_ms,
        ROUND(AVG(burst_cost_per_mbps_usd) OVER(PARTITION BY pop_location), 2) AS pop_avg_burst_cost,
        ROUND(
            p95_throughput_mbps / NULLIF(cir_mbps, 0) * 100.0, 
            1
        ) AS cir_utilization_pct,
        CASE 
            WHEN p95_throughput_mbps > cir_mbps 
            THEN ROUND((p95_throughput_mbps - cir_mbps) * burst_cost_per_mbps_usd, 2)
            ELSE 0.00
        END AS estimated_monthly_burst_penalty_usd
    FROM pop_traffic_aggregates
)
SELECT 
    pop_location,
    circuit_id,
    carrier_name,
    cir_mbps,
    p95_throughput_mbps,
    cir_utilization_pct,
    latency_sla_ms,
    pop_avg_latency_ms,
    ROUND(latency_sla_ms - pop_avg_latency_ms, 2) AS latency_delta_vs_regional_baseline_ms,
    burst_cost_per_mbps_usd,
    pop_avg_burst_cost,
    base_cost_usd_month,
    estimated_monthly_burst_penalty_usd,
    CASE 
        WHEN latency_sla_ms < pop_avg_latency_ms AND estimated_monthly_burst_penalty_usd = 0.0 
            THEN 'PREMIUM TIER: Low Latency / Zero Penalty (Optimal Primary Route)'
        WHEN latency_sla_ms < pop_avg_latency_ms AND estimated_monthly_burst_penalty_usd > 0.0 
            THEN 'LATENCY CRITICAL: Bursting Detected (Expand Commit Tier)'
        WHEN latency_sla_ms >= pop_avg_latency_ms AND estimated_monthly_burst_penalty_usd = 0.0 
            THEN 'STANDARD BULK: Efficient Secondary Egress'
        ELSE 'EXPENSIVE OVERUSE: High Latency & High Burst Penalty (Deprioritize Routing)'
    END AS routing_policy_classification
FROM regional_benchmarks
ORDER BY pop_location, latency_sla_ms ASC;
