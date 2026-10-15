"""
src/domain/entities.py - Pure domain models for CommandLink Cost Optimization Engine.
Zero external I/O or vendor dependencies imported here.
"""

from typing import List, Dict, Optional
from pydantic import BaseModel, Field


class CircuitLink(BaseModel):
    """Represents a physical/virtual telecom transit link or SD-WAN circuit."""
    link_id: str
    carrier_name: str
    pop_location: str
    committed_information_rate_mbps: float = Field(gt=0, description="CIR in Mbps paid as fixed base")
    peak_information_rate_mbps: float = Field(gt=0, description="PIR / Physical link burst capacity")
    base_cost_usd_month: float = Field(ge=0, description="Monthly recurring charge (MRC) for CIR")
    burst_cost_per_mbps_usd: float = Field(ge=0, description="Over-quota charge per Mbps above CIR (95th percentile)")
    latency_ms: float = Field(ge=0, description="Average nominal latency SLA")
    contract_term_months: int = Field(default=36, description="Total contracted duration")
    months_active: int = Field(default=12, description="Current circuit tenure")
    sla_breaches_count: int = Field(default=0, description="Recorded outage/degradation events")


class TrafficSample(BaseModel):
    """A 5-minute telemetry point representing transit volume."""
    timestamp_epoch: int
    link_id: str
    egress_mbps: float = Field(ge=0)
    ingress_mbps: float = Field(ge=0)
    aggregate_mbps: float = Field(ge=0)


class CarrierAllocation(BaseModel):
    """Optimal traffic distribution for a single circuit."""
    link_id: str
    carrier_name: str
    allocated_mbps: float
    effective_95th_mbps: float
    is_bursting: bool
    monthly_cost_usd: float
    savings_vs_unmanaged_usd: float


class OptimizationResult(BaseModel):
    """Aggregate solution output from the Linear Programming Solver."""
    solver_status: str
    is_optimal: bool
    execution_time_ms: float
    total_managed_demand_mbps: float
    total_optimized_cost_usd: float
    unmanaged_baseline_cost_usd: float
    net_monthly_savings_usd: float
    savings_percentage: float
    carrier_allocations: List[CarrierAllocation]


class ContractSurvivalMetrics(BaseModel):
    """Causal & Survival analysis metrics for circuit contract lifecycles."""
    link_id: str
    carrier_name: str
    tenure_months: int
    survival_probability: float = Field(description="Kaplan-Meier estimate S(t) = P(Tenure > t)")
    hazard_ratio: float = Field(description="Cox PH relative risk of premature termination/churn")
    renegotiation_urgency: str = Field(description="LOW, MEDIUM, HIGH, CRITICAL")
    suggested_action: str