-- ==============================================================================
-- CommandLink Telecom Lakehouse - DDL & Partitioning Schema
-- Target: PostgreSQL 16 Enterprise / Amazon RDS Aurora
-- Role: Cost Optimization Analyst
-- Domain: Multi-Carrier SD-WAN Telemetry, 95th Percentile Burstable Billing
-- ==============================================================================

CREATE SCHEMA IF NOT EXISTS telecom_lakehouse;
SET search_path TO telecom_lakehouse, public;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Reference Table: Multi-Carrier Circuit Link Catalog
CREATE TABLE IF NOT EXISTS circuits_catalog (
    circuit_id VARCHAR(32) PRIMARY KEY,
    carrier_name VARCHAR(64) NOT NULL,
    pop_location VARCHAR(64) NOT NULL,
    committed_information_rate_mbps NUMERIC(10, 2) NOT NULL,
    peak_information_rate_mbps NUMERIC(10, 2) NOT NULL,
    base_cost_usd_month NUMERIC(12, 2) NOT NULL,
    burst_cost_per_mbps_usd NUMERIC(8, 2) NOT NULL,
    latency_sla_ms NUMERIC(6, 2) NOT NULL,
    contract_term_months INT NOT NULL DEFAULT 36,
    months_active INT NOT NULL DEFAULT 12,
    sla_breaches_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Master Traffic Telemetry: Range-Partitioned by Event Timestamp (5-minute intervals)
CREATE TABLE IF NOT EXISTS traffic_telemetry (
    telemetry_id UUID DEFAULT uuid_generate_v4(),
    circuit_id VARCHAR(32) NOT NULL,
    carrier_name VARCHAR(64) NOT NULL,
    aggregate_mbps NUMERIC(10, 2) NOT NULL,
    egress_mbps NUMERIC(10, 2) NOT NULL,
    ingress_mbps NUMERIC(10, 2) NOT NULL,
    event_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_traffic_telemetry PRIMARY KEY (event_timestamp, telemetry_id)
) PARTITION BY RANGE (event_timestamp);

-- Monthly Operational Partitions
CREATE TABLE IF NOT EXISTS traffic_telemetry_2026_01 PARTITION OF traffic_telemetry
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS traffic_telemetry_2026_02 PARTITION OF traffic_telemetry
    FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS traffic_telemetry_default PARTITION OF traffic_telemetry
    DEFAULT;

-- BRIN Index on event_timestamp for high-throughput append storage
CREATE INDEX IF NOT EXISTS idx_traffic_telemetry_brin_timestamp 
    ON traffic_telemetry USING BRIN (event_timestamp) 
    WITH (pages_per_range = 32);

-- B-Tree composite index for circuit lookup and window slicing
CREATE INDEX IF NOT EXISTS idx_traffic_telemetry_circuit_time 
    ON traffic_telemetry (circuit_id, event_timestamp DESC);