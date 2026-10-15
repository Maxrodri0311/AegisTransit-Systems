"""
tests/test_suite.py - Unit & Integration Test Suite for CommandLink Cost Optimization Engine.
Tests linear programming demand conservation, PIR constraints, and survival hazards.
Strictly decoupled using InMemoryTelemetryStorage for sub-5ms test runs.
"""

import sys
from pathlib import Path
import pytest
import numpy as np

# Path resolution
project_root = str(Path(__file__).resolve().parent.parent)
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from src.domain.entities import CircuitLink, TrafficSample
from src.core_engine import (
    InMemoryTelemetryStorage,
    LinearTransitOptimizer,
    ContractSurvivalAnalyzer,
    CostOptimizationEngine,
)


@pytest.fixture
def sample_circuits():
    return [
        CircuitLink(
            link_id="L-1",
            carrier_name="Lumen",
            pop_location="ORD-1",
            committed_information_rate_mbps=1000.0,
            peak_information_rate_mbps=2500.0,
            base_cost_usd_month=1500.0,
            burst_cost_per_mbps_usd=2.00,
            latency_ms=15.0,
            contract_term_months=36,
            months_active=10,
            sla_breaches_count=0
        ),
        CircuitLink(
            link_id="L-2",
            carrier_name="Cogent",
            pop_location="JFK-2",
            committed_information_rate_mbps=2000.0,
            peak_information_rate_mbps=5000.0,
            base_cost_usd_month=1800.0,
            burst_cost_per_mbps_usd=1.60,
            latency_ms=20.0,
            contract_term_months=36,
            months_active=28,
            sla_breaches_count=3
        ),
        CircuitLink(
            link_id="L-3",
            carrier_name="Zayo",
            pop_location="DFW-1",
            committed_information_rate_mbps=1500.0,
            peak_information_rate_mbps=3000.0,
            base_cost_usd_month=1600.0,
            burst_cost_per_mbps_usd=2.50,
            latency_ms=14.0,
            contract_term_months=36,
            months_active=18,
            sla_breaches_count=1
        ),
    ]


def test_in_memory_storage_sub5ms(sample_circuits):
    storage = InMemoryTelemetryStorage(links=sample_circuits)
    retrieved = storage.get_links()
    assert len(retrieved) == 3
    assert storage.compute_95th_percentile("L-1") == 1000.0


def test_linear_optimizer_demand_conservation(sample_circuits):
    optimizer = LinearTransitOptimizer()
    target_demand = 3500.0
    result = optimizer.solve(links=sample_circuits, target_demand_mbps=target_demand)

    assert result.is_optimal is True
    total_allocated = sum(a.allocated_mbps for a in result.carrier_allocations)
    assert abs(total_allocated - target_demand) < 1e-2


def test_linear_optimizer_pir_bounds(sample_circuits):
    optimizer = LinearTransitOptimizer()
    target_demand = 8000.0  # Requires bursting across carriers
    result = optimizer.solve(links=sample_circuits, target_demand_mbps=target_demand)

    assert result.is_optimal is True
    link_map = {l.link_id: l for l in sample_circuits}
    for alloc in result.carrier_allocations:
        pir = link_map[alloc.link_id].peak_information_rate_mbps
        assert alloc.allocated_mbps <= pir + 1e-2


def test_linear_optimizer_cost_minimization(sample_circuits):
    """Verifies that LP optimized cost is strictly <= naive unmanaged baseline."""
    optimizer = LinearTransitOptimizer()
    target_demand = 5500.0
    result = optimizer.solve(links=sample_circuits, target_demand_mbps=target_demand)

    assert result.total_optimized_cost_usd <= result.unmanaged_baseline_cost_usd
    assert result.net_monthly_savings_usd >= 0.0


def test_contract_survival_monotonicity(sample_circuits):
    analyzer = ContractSurvivalAnalyzer()
    metrics = analyzer.estimate_survival(sample_circuits)

    assert len(metrics) == 3
    # L-2 has 28 months active + 3 breaches vs L-1 with 10 months + 0 breaches
    m_l1 = next(m for m in metrics if m.link_id == "L-1")
    m_l2 = next(m for m in metrics if m.link_id == "L-2")

    assert m_l2.hazard_ratio > m_l1.hazard_ratio
    assert m_l1.survival_probability > m_l2.survival_probability
    assert m_l2.renegotiation_urgency in ["HIGH", "CRITICAL"]


def test_end_to_end_clean_architecture_orchestrator(sample_circuits):
    storage = InMemoryTelemetryStorage(links=sample_circuits)
    optimizer = LinearTransitOptimizer()
    analyzer = ContractSurvivalAnalyzer()

    engine = CostOptimizationEngine(
        storage=storage,
        optimizer=optimizer,
        survival_analyzer=analyzer
    )

    cycle_output = engine.run_optimization_cycle(target_demand_mbps=4000.0, latency_budget_ms=25.0)
    assert "optimization" in cycle_output
    assert "survival" in cycle_output
    assert cycle_output["optimization"].is_optimal is True
    assert len(cycle_output["survival"]) == 3