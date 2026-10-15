-- ==============================================================================
-- CommandLink Carrier Contract Survival & Churn Hazard Cohort Analysis
-- Target: PostgreSQL 16 Enterprise
-- Calculates empirical survival rates S(t) and contract attrition risk
-- ==============================================================================

SET search_path TO telecom_lakehouse, public;

WITH contract_cohorts AS (
    SELECT 
        carrier_name,
        pop_location,
        contract_term_months,
        months_active,
        sla_breaches_count,
        ROUND((months_active::NUMERIC / NULLIF(contract_term_months, 0)) * 100, 1) AS term_completion_pct,
        CASE 
            WHEN months_active < 12 THEN '0-12m (Early Onboarding)'
            WHEN months_active BETWEEN 12 AND 24 THEN '12-24m (Mid-Term)'
            WHEN months_active BETWEEN 25 AND 35 THEN '25-35m (Pre-Renewal)'
            ELSE '36m+ (Expired/Month-to-Month)'
        END AS tenure_cohort,
        base_cost_usd_month,
        burst_cost_per_mbps_usd
    FROM circuits_catalog
),
hazard_aggregations AS (
    SELECT 
        tenure_cohort,
        COUNT(*) AS total_circuits,
        ROUND(AVG(sla_breaches_count), 2) AS mean_sla_breaches,
        ROUND(AVG(burst_cost_per_mbps_usd), 2) AS avg_burst_rate,
        ROUND(SUM(base_cost_usd_month), 2) AS cohort_base_mrc_usd,
        ROUND(
            AVG(
                EXP(
                    (sla_breaches_count * 0.45) + 
                    ((burst_cost_per_mbps_usd / 2.30 - 1.0) * 0.85) + 
                    (term_completion_pct / 100.0 * 0.70)
                )
            ),
            3
        ) AS cohort_mean_hazard_score
    FROM contract_cohorts
    GROUP BY tenure_cohort
)
SELECT 
    tenure_cohort,
    total_circuits,
    cohort_base_mrc_usd,
    mean_sla_breaches,
    avg_burst_rate,
    cohort_mean_hazard_score,
    CASE 
        WHEN cohort_mean_hazard_score >= 2.5 THEN 'IMMEDIATE CONTRACT RE-NEGOTIATION / RFP'
        WHEN cohort_mean_hazard_score >= 1.5 THEN 'ACTIVE SLA CREDIT MONITORING'
        ELSE 'STEADY-STATE RETENTION'
    END AS strategic_recommendation
FROM hazard_aggregations
ORDER BY cohort_mean_hazard_score DESC;