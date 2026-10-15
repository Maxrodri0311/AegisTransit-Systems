-- ==============================================================================
-- CommandLink Analytical Lakehouse - PL/pgSQL Procedural Functions & Audit Triggers
-- Target: PostgreSQL 16 Enterprise / Aurora
-- Role: Cost Optimization Analyst
-- Features: Transactional Integrity, Batch Cursor Processing & Anomaly Auditing
-- ==============================================================================

SET search_path TO analytical_lakehouse, public;

-- Audit Ledger for High-Risk Events
CREATE TABLE IF NOT EXISTS commandlink_cost_optimization_analyst_bridge_project_anomaly_audit_ledger (
    audit_id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    entity_id VARCHAR(64) NOT NULL,
    detected_tier VARCHAR(32) NOT NULL,
    payload_snapshot JSONB NOT NULL,
    audited_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    acknowledged BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_commandlink_cost_optimization_analyst_bridge_project_audit_unacknowledged 
    ON commandlink_cost_optimization_analyst_bridge_project_anomaly_audit_ledger (entity_id, audited_at DESC)
    WHERE acknowledged = FALSE;

-- Procedural Stored Function for Real-Time Event Triage
CREATE OR REPLACE FUNCTION fn_audit_commandlink_cost_optimization_analyst_bridge_project_event(
    p_entity_id VARCHAR(64),
    p_domain_cluster VARCHAR(32),
    p_event_data JSONB
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_audit_id UUID;
BEGIN
    INSERT INTO commandlink_cost_optimization_analyst_bridge_project_anomaly_audit_ledger (
        entity_id,
        detected_tier,
        payload_snapshot
    ) VALUES (
        p_entity_id,
        'REAL_TIME_DISPATCH',
        p_event_data
    )
    RETURNING audit_id INTO v_audit_id;

    RETURN v_audit_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '[Audit Error] Failed to record audit for entity %: %', p_entity_id, SQLERRM;
        RETURN NULL;
END;
$$;