"""
tests/benchmark.py - Quantitative Latency Benchmark for AegisTransit Cost Optimizer.
Measures p50, p90, p95, and p99 solver latency over 50 dynamic traffic optimization cycles.
Enforces strict SLA constraints: p95 < 150.0 ms.
"""

import sys
import time
from pathlib import Path
import numpy as np

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Path resolution
project_root = str(Path(__file__).resolve().parent.parent)
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from src.data_generator import generate_reference_circuits
from src.core_engine import (
    InMemoryTelemetryStorage,
    LinearTransitOptimizer,
    ContractSurvivalAnalyzer,
    CostOptimizationEngine,
)


def run_benchmark(iterations: int = 50, enforce_sla: bool = True):
    print(f"[Benchmark] Initializing decoupled engine with {iterations} iterations...")
    circuits = generate_reference_circuits(seed=42)
    storage = InMemoryTelemetryStorage(links=circuits)
    optimizer = LinearTransitOptimizer()
    survival_analyzer = ContractSurvivalAnalyzer()

    engine = CostOptimizationEngine(
        storage=storage,
        optimizer=optimizer,
        survival_analyzer=survival_analyzer
    )

    # Warmup
    engine.run_optimization_cycle(target_demand_mbps=8500.0, latency_budget_ms=25.0)

    latencies_ms = []
    rng = np.random.default_rng(123)

    for i in range(iterations):
        demand = float(rng.uniform(5000.0, 11500.0))
        lat_budget = float(rng.uniform(18.0, 30.0))

        t0 = time.perf_counter()
        engine.run_optimization_cycle(target_demand_mbps=demand, latency_budget_ms=lat_budget)
        elapsed = (time.perf_counter() - t0) * 1000.0
        latencies_ms.append(elapsed)

    p50 = float(np.percentile(latencies_ms, 50))
    p90 = float(np.percentile(latencies_ms, 90))
    p95 = float(np.percentile(latencies_ms, 95))
    p99 = float(np.percentile(latencies_ms, 99))
    min_lat = float(np.min(latencies_ms))
    max_lat = float(np.max(latencies_ms))

    print("\n" + "="*70)
    print("  AEGISTRANSIT OPTIMIZER - QUANTITATIVE LATENCY BENCHMARK (ms)")
    print("="*70)
    print(f"  Iterations:     {iterations}")
    print(f"  Min Latency:    {min_lat:.2f} ms")
    print(f"  p50 Latency:    {p50:.2f} ms")
    print(f"  p90 Latency:    {p90:.2f} ms")
    print(f"  p95 Latency:    {p95:.2f} ms (SLA Target: < 150.0 ms)")
    print(f"  p99 Latency:    {p99:.2f} ms")
    print(f"  Max Latency:    {max_lat:.2f} ms")
    print("="*70)

    if enforce_sla:
        assert p95 < 150.0, f"SLA Violation: p95 latency {p95:.2f} ms exceeded 150.0 ms threshold"
        print("[Benchmark] [PASS] SLA VERIFIED: Sub-150ms P95 constraint passed successfully.\n")


if __name__ == "__main__":
    run_benchmark(iterations=50)