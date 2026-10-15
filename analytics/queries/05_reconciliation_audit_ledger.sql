-- ==============================================================================
-- AegisTransit Telemetry Lakehouse - Carrier Invoice vs Telemetry Reconciliation
-- Target: PostgreSQL 16 Enterprise
-- Detects carrier billing overcharges, inaccurate 95th-percentile rounding, and SLA breaches
-- ==============================================================================

SET search_path TO telecom_lakehouse, public;

CREATE TABLE IF NOT EXISTS carrier_invoiced_records (
    invoice_id VARCHAR(64) PRIMARY KEY,
    circuit_id VARCHAR(32) NOT NULL,
    carrier_name VARCHAR(64) NOT NULL,
    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,
    carrier_claimed_95th_mbps NUMERIC(10, 2) NOT NULL,
    carrier_invoiced_base_mrc_usd NUMERIC(12, 2) NOT NULL,
    carrier_invoiced_burst_usd NUMERIC(12, 2) NOT NULL,
    carrier_invoiced_total_usd NUMERIC(12, 2) NOT NULL,
    invoiced_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE VIEW v_carrier_invoice_reconciliation_audit AS
WITH internal_monthly_aggregates AS (
    SELECT 
        DATE_TRUNC('month', t.event_timestamp)::DATE AS billing_period_start,
        t.circuit_id,
        t.carrier_name,
        c.committed_information_rate_mbps AS contracted_cir_mbps,
        c.burst_cost_per_mbps_usd AS contracted_burst_rate,
        c.base_cost_usd_month AS contracted_base_mrc,
        COUNT(t.telemetry_id) AS total_5min_samples_recorded,
        ROUND(
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY t.aggregate_mbps)::NUMERIC, 
            2
        ) AS internal_verified_95th_mbps,
        ROUND(
            GREATEST(0.0, PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY t.aggregate_mbps) - c.committed_information_rate_mbps) * c.burst_cost_per_mbps_usd,
            2
        ) AS internal_verified_burst_usd,
        ROUND(
            c.base_cost_usd_month + (
                GREATEST(0.0, PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY t.aggregate_mbps) - c.committed_information_rate_mbps) * c.burst_cost_per_mbps_usd
            ),
            2
        ) AS internal_verified_total_usd
    FROM traffic_telemetry t
    JOIN circuits_catalog c ON t.circuit_id = c.circuit_id
    GROUP BY 
        DATE_TRUNC('month', t.event_timestamp)::DATE,
        t.circuit_id,
        t.carrier_name,
        c.committed_information_rate_mbps,
        c.burst_cost_per_mbps_usd,
        c.base_cost_usd_month
),
discrepancy_ledger AS (
    SELECT 
        inv.invoice_id,
        int_agg.circuit_id,
        int_agg.carrier_name,
        int_agg.billing_period_start,
        int_agg.internal_verified_95th_mbps,
        inv.carrier_claimed_95th_mbps,
        ROUND(inv.carrier_claimed_95th_mbps - int_agg.internal_verified_95th_mbps, 2) AS bandwidth_discrepancy_mbps,
        int_agg.internal_verified_total_usd,
        inv.carrier_invoiced_total_usd,
        ROUND(inv.carrier_invoiced_total_usd - int_agg.internal_verified_total_usd, 2) AS financial_overcharge_usd,
        CASE 
            WHEN inv.carrier_invoiced_total_usd > (int_agg.internal_verified_total_usd + 25.0) 
                THEN 'FLAGGED OVERCHARGE: Dispute required with carrier vendor billing'
            WHEN inv.carrier_invoiced_total_usd < (int_agg.internal_verified_total_usd - 25.0) 
                THEN 'UNDERBILLED: Carrier concession or internal unrecorded credit'
            ELSE 'RECONCILED: Within contractual tolerance window (<= $25.00)'
        END AS audit_reconciliation_verdict
    FROM internal_monthly_aggregates int_agg
    JOIN carrier_invoiced_records inv 
        ON int_agg.circuit_id = inv.circuit_id 
        AND int_agg.billing_period_start = inv.billing_period_start
)
SELECT 
    invoice_id,
    circuit_id,
    carrier_name,
    billing_period_start,
    internal_verified_95th_mbps,
    carrier_claimed_95th_mbps,
    bandwidth_discrepancy_mbps,
    internal_verified_total_usd,
    carrier_invoiced_total_usd,
    financial_overcharge_usd,
    audit_reconciliation_verdict
FROM discrepancy_ledger
ORDER BY financial_overcharge_usd DESC;
