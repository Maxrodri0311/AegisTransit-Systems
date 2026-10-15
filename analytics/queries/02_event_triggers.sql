-- ==============================================================================
-- AegisTransit Telemetry Lakehouse - PL/pgSQL Procedural Functions & Audit Triggers
-- Target: PostgreSQL 16 Enterprise / Aurora
-- Domain: Telecom Transit Burstable Billing & Contract Anomaly Auditing
-- ==============================================================================

SET search_path TO telecom_lakehouse, public;

-- Audit Ledger for High-Risk Burst & Hazard Events
CREATE TABLE IF NOT EXISTS telecom_transit_anomaly_audit_ledger (
    audit_id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    circuit_id VARCHAR(32) NOT NULL,
    detected_severity VARCHAR(32) NOT NULL,
    payload_snapshot JSONB NOT NULL,
    audited_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    acknowledged BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_transit_audit_unacknowledged 
    ON telecom_transit_anomaly_audit_ledger (circuit_id, audited_at DESC)
    WHERE acknowledged = FALSE;

-- Procedural Stored Function for Real-Time Burst Anomaly Triage
CREATE OR REPLACE FUNCTION fn_audit_burst_overage_event(
    p_circuit_id VARCHAR(32),
    p_severity VARCHAR(32),
    p_event_data JSONB
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_audit_id UUID;
BEGIN
    INSERT INTO telecom_transit_anomaly_audit_ledger (
        circuit_id,
        detected_severity,
        payload_snapshot
    ) VALUES (
        p_circuit_id,
        p_severity,
        p_event_data
    )
    RETURNING audit_id INTO v_audit_id;

    RETURN v_audit_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '[Audit Error] Failed to record audit for circuit %: %', p_circuit_id, SQLERRM;
        RETURN NULL;
END;
$$;