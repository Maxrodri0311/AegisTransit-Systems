-- ==============================================================================
-- AegisTransit Telemetry Lakehouse - Carrier SLA Credit Recovery Pipeline
-- Target: PostgreSQL 16 Enterprise
-- Computes contractual monetary penalties for SLA breaches, jitter, and packet degradation
-- ==============================================================================

SET search_path TO telecom_lakehouse, public;

CREATE TABLE IF NOT EXISTS sla_incident_event_ledger (
    incident_id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    circuit_id VARCHAR(32) NOT NULL,
    incident_start TIMESTAMPTZ NOT NULL,
    incident_end TIMESTAMPTZ NOT NULL,
    recorded_latency_ms NUMERIC(6, 2) NOT NULL,
    sla_threshold_latency_ms NUMERIC(6, 2) NOT NULL,
    packet_loss_pct NUMERIC(5, 2) NOT NULL DEFAULT 0.0,
    carrier_ticket_ref VARCHAR(64),
    credit_claim_status VARCHAR(32) NOT NULL DEFAULT 'PENDING_SUBMISSION'
);

CREATE OR REPLACE VIEW v_monthly_sla_credit_recovery_summary AS
WITH monthly_incidents AS (
    SELECT 
        DATE_TRUNC('month', inc.incident_start)::DATE AS incident_month,
        inc.circuit_id,
        c.carrier_name,
        c.pop_location,
        c.base_cost_usd_month AS circuit_mrc_usd,
        COUNT(inc.incident_id) AS total_monthly_breaches,
        ROUND(SUM(EXTRACT(EPOCH FROM (inc.incident_end - inc.incident_start)) / 3600.0)::NUMERIC, 2) AS total_outage_hours,
        ROUND(AVG(inc.recorded_latency_ms), 2) AS mean_degraded_latency_ms,
        ROUND(AVG(inc.packet_loss_pct), 2) AS mean_packet_loss_pct
    FROM sla_incident_event_ledger inc
    JOIN circuits_catalog c ON inc.circuit_id = c.circuit_id
    GROUP BY 
        DATE_TRUNC('month', inc.incident_start)::DATE,
        inc.circuit_id,
        c.carrier_name,
        c.pop_location,
        c.base_cost_usd_month
),
contractual_credit_calculations AS (
    SELECT 
        incident_month,
        circuit_id,
        carrier_name,
        pop_location,
        circuit_mrc_usd,
        total_monthly_breaches,
        total_outage_hours,
        mean_degraded_latency_ms,
        mean_packet_loss_pct,
        -- Standard enterprise MSA tier:
        -- Outage > 4 hours: 10% MRC credit
        -- Outage > 8 hours: 25% MRC credit
        -- Outage > 24 hours: 50% MRC credit
        CASE 
            WHEN total_outage_hours >= 24.0 THEN 0.50
            WHEN total_outage_hours >= 8.0  THEN 0.25
            WHEN total_outage_hours >= 4.0  THEN 0.10
            WHEN total_monthly_breaches >= 3 THEN 0.15
            ELSE 0.05
        END AS contractual_credit_percentage
    FROM monthly_incidents
)
SELECT 
    incident_month,
    circuit_id,
    carrier_name,
    pop_location,
    circuit_mrc_usd,
    total_monthly_breaches,
    total_outage_hours,
    ROUND(contractual_credit_percentage * 100.0, 1) AS credit_pct_rate,
    ROUND(circuit_mrc_usd * contractual_credit_percentage, 2) AS enforceable_credit_recovery_usd,
    ROUND(circuit_mrc_usd * (1.0 - contractual_credit_percentage), 2) AS adjusted_net_payable_mrc_usd,
    CASE 
        WHEN contractual_credit_percentage >= 0.25 
            THEN 'TIER-1 ESCALATION: Severe service degradation, submit formal credit claim to VP of Carrier Relations'
        WHEN contractual_credit_percentage >= 0.10 
            THEN 'TIER-2 CLAIM: Standard breach threshold met, attach telemetry CSV to vendor invoice payment deduction'
        ELSE 'MONITORED: Minor threshold event, log for quarterly vendor review meeting'
    END AS billing_recovery_directive
FROM contractual_credit_calculations
ORDER BY enforceable_credit_recovery_usd DESC;
