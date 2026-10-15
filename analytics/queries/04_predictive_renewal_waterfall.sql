-- ==============================================================================
-- AegisTransit Telecom Lakehouse - Predictive Renewal Cashflow Waterfall
-- Target: PostgreSQL 16 Enterprise
-- Simulates 12-month forward-looking financial impact of circuit contract renegotiation
-- ==============================================================================

SET search_path TO telecom_lakehouse, public;

CREATE OR REPLACE VIEW v_predictive_contract_renewal_waterfall AS
WITH forward_projections AS (
    SELECT 
        c.circuit_id,
        c.carrier_name,
        c.pop_location,
        c.contract_term_months,
        c.months_active,
        c.base_cost_usd_month,
        c.burst_cost_per_mbps_usd,
        c.sla_breaches_count,
        (c.contract_term_months - c.months_active) AS months_to_expiration,
        -- Projected annual baseline cost without optimization
        ROUND(c.base_cost_usd_month * 12.0, 2) AS current_annual_mrc_usd,
        -- Cox Proportional Hazard score
        ROUND(
            EXP(
                (c.sla_breaches_count * 0.45) + 
                ((c.burst_cost_per_mbps_usd / 2.30 - 1.0) * 0.85) + 
                (c.months_active::NUMERIC / NULLIF(c.contract_term_months, 0) * 0.70)
            ), 
            3
        ) AS contract_hazard_ratio
    FROM circuits_catalog c
),
waterfall_scenarios AS (
    SELECT 
        circuit_id,
        carrier_name,
        pop_location,
        months_active,
        months_to_expiration,
        current_annual_mrc_usd,
        contract_hazard_ratio,
        -- Target benchmark negotiation discount: 15% to 28% depending on breach count and tenure
        CASE 
            WHEN contract_hazard_ratio >= 2.5 THEN 0.28
            WHEN contract_hazard_ratio >= 1.5 THEN 0.18
            ELSE 0.10
        END AS targeted_renegotiation_discount_rate,
        CASE 
            WHEN months_to_expiration <= 6 THEN 'Q1-Q2 Immediate Priority'
            WHEN months_to_expiration <= 12 THEN 'Q3-Q4 Upcoming Pipeline'
            ELSE 'Mid-Term Hold'
        END AS negotiation_time_horizon
    FROM forward_projections
)
SELECT 
    circuit_id,
    carrier_name,
    pop_location,
    months_active,
    months_to_expiration,
    negotiation_time_horizon,
    contract_hazard_ratio,
    current_annual_mrc_usd,
    ROUND(targeted_renegotiation_discount_rate * 100.0, 1) AS target_discount_pct,
    ROUND(current_annual_mrc_usd * targeted_renegotiation_discount_rate, 2) AS projected_annual_cost_savings_usd,
    ROUND(current_annual_mrc_usd * (1.0 - targeted_renegotiation_discount_rate), 2) AS post_renegotiation_annual_mrc_usd,
    CASE 
        WHEN contract_hazard_ratio >= 2.5 
            THEN 'INITIATE AGGRESSIVE CARRIER RFP: High SLA breaches justify competitive discount or exit'
        WHEN contract_hazard_ratio >= 1.5 
            THEN 'EXERCISE SLA PENALTY OFFSETS: Rebalance commitment tiers prior to renewal window'
        ELSE 'EXTEND CONTRACT AT STEADY-STATE: Terms are commercially competitive'
    END AS strategic_action_directive
FROM waterfall_scenarios
ORDER BY projected_annual_cost_savings_usd DESC;
