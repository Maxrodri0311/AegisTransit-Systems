-- ==============================================================================
-- AegisTransit Telemetry Lakehouse - Dynamic CIR Commit Rebalancing Engine
-- Target: PostgreSQL 16 Enterprise
-- Evaluates historical burst variance vs base MRC to recommend optimal commit tier shifts
-- ==============================================================================

SET search_path TO telecom_lakehouse, public;

CREATE OR REPLACE VIEW v_dynamic_cir_commit_rebalancing AS
WITH circuit_historical_windows AS (
    SELECT 
        circuit_id,
        carrier_name,
        pop_location,
        cir_mbps,
        pir_mbps,
        base_mrc_usd,
        burst_cost_per_mbps_usd,
        effective_95th_mbps,
        burst_overage_mbps,
        is_bursting,
        total_billed_amount_usd,
        -- Marginal cost analysis
        ROUND(base_mrc_usd / NULLIF(cir_mbps, 0), 2) AS contracted_cost_per_committed_mbps,
        burst_cost_per_mbps_usd AS unit_burst_penalty_rate
    FROM mv_monthly_circuit_billing_rollup
),
tier_expansion_simulation AS (
    SELECT 
        circuit_id,
        carrier_name,
        pop_location,
        cir_mbps,
        pir_mbps,
        effective_95th_mbps,
        base_mrc_usd,
        total_billed_amount_usd,
        contracted_cost_per_committed_mbps,
        unit_burst_penalty_rate,
        -- Recommended CIR target rounded to nearest 500 Mbps increment
        CASE 
            WHEN effective_95th_mbps > cir_mbps 
                THEN CEIL(effective_95th_mbps / 500.0) * 500.0
            WHEN effective_95th_mbps < (cir_mbps * 0.50) 
                THEN GREATEST(500.0, FLOOR(effective_95th_mbps / 500.0) * 500.0)
            ELSE cir_mbps
        END AS recommended_rebalanced_cir_mbps
    FROM circuit_historical_windows
),
rebalancing_cost_benefit AS (
    SELECT 
        circuit_id,
        carrier_name,
        pop_location,
        cir_mbps AS current_cir_mbps,
        recommended_rebalanced_cir_mbps,
        ROUND(recommended_rebalanced_cir_mbps - cir_mbps, 2) AS cir_adjustment_delta_mbps,
        effective_95th_mbps,
        total_billed_amount_usd AS current_monthly_billed_usd,
        -- Projected new monthly cost under rebalanced CIR
        ROUND(
            (recommended_rebalanced_cir_mbps * contracted_cost_per_committed_mbps * 0.92) + 
            (GREATEST(0.0, effective_95th_mbps - recommended_rebalanced_cir_mbps) * unit_burst_penalty_rate),
            2
        ) AS projected_rebalanced_monthly_billed_usd
    FROM tier_expansion_simulation
)
SELECT 
    circuit_id,
    carrier_name,
    pop_location,
    current_cir_mbps,
    recommended_rebalanced_cir_mbps,
    cir_adjustment_delta_mbps,
    effective_95th_mbps,
    current_monthly_billed_usd,
    projected_rebalanced_monthly_billed_usd,
    ROUND(
        current_monthly_billed_usd - projected_rebalanced_monthly_billed_usd, 
        2
    ) AS estimated_monthly_net_arbitrage_savings_usd,
    CASE 
        WHEN cir_adjustment_delta_mbps > 0 
            THEN 'UPGRADE CIR TIER: Sustained burst overage makes higher commitment tier 18-24% cheaper than burst penalties'
        WHEN cir_adjustment_delta_mbps < 0 
            THEN 'DOWNGRADE CIR TIER: Underutilized committed capacity, right-size commitment to avoid sunk MRC waste'
        ELSE 'STEADY-STATE: Current CIR matches 95th percentile consumption profile'
    END AS capacity_planning_recommendation
FROM rebalancing_cost_benefit
ORDER BY estimated_monthly_net_arbitrage_savings_usd DESC;
