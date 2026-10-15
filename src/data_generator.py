"""
src/data_generator.py - Stochastic Telecom Transit & SD-WAN Telemetry Generator.
Simulates realistic multi-carrier transit links, 95th percentile burst windows,
and contract survival lifecycles for AegisTransit Systems.
"""

import os
import sys
import time
import argparse
from pathlib import Path
from typing import List, Tuple
import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from src.domain.entities import CircuitLink, TrafficSample


CARRIERS_CATALOG = [
    {"name": "Apex Fiber Transit", "pop": "ORD-1 (Chicago)", "base_cir": 2000.0, "pir_factor": 2.5, "base_cost": 2200.0, "burst_rate": 2.10, "sla_lat": 16.5},
    {"name": "Vanguard Backbone", "pop": "JFK-2 (New York)", "base_cir": 3000.0, "pir_factor": 3.0, "base_cost": 1850.0, "burst_rate": 1.75, "sla_lat": 22.0},
    {"name": "Meridian Metro Optical", "pop": "DFW-1 (Dallas)", "base_cir": 1500.0, "pir_factor": 2.0, "base_cost": 1950.0, "burst_rate": 2.45, "sla_lat": 14.8},
    {"name": "Atlantic Carrier Services", "pop": "ATL-2 (Atlanta)", "base_cir": 2500.0, "pir_factor": 2.2, "base_cost": 3100.0, "burst_rate": 3.20, "sla_lat": 13.5},
    {"name": "Summit Broadband", "pop": "ORD-1 (Chicago)", "base_cir": 1000.0, "pir_factor": 2.0, "base_cost": 1100.0, "burst_rate": 2.60, "sla_lat": 24.2},
    {"name": "Pacific Dynamic Transit", "pop": "SJC-1 (Silicon Valley)", "base_cir": 2000.0, "pir_factor": 2.5, "base_cost": 2800.0, "burst_rate": 2.90, "sla_lat": 17.1},
]


def generate_reference_circuits(seed: int = 42) -> List[CircuitLink]:
    """Generates the reference multi-carrier circuits for enterprise PoP routing."""
    rng = np.random.default_rng(seed)
    circuits: List[CircuitLink] = []

    for idx, template in enumerate(CARRIERS_CATALOG, start=1):
        cir = float(template["base_cir"])
        pir = float(cir * template["pir_factor"])
        tenure = int(rng.integers(6, 34))
        sla_breaches = int(rng.poisson(lam=1.2))

        link = CircuitLink(
            link_id=f"CIRCUIT-{idx:03d}",
            carrier_name=template["name"],
            pop_location=template["pop"],
            committed_information_rate_mbps=cir,
            peak_information_rate_mbps=pir,
            base_cost_usd_month=float(template["base_cost"]),
            burst_cost_per_mbps_usd=float(template["burst_rate"]),
            latency_ms=float(template["sla_lat"] + rng.uniform(-1.5, 2.5)),
            contract_term_months=36,
            months_active=tenure,
            sla_breaches_count=sla_breaches
        )
        circuits.append(link)

    return circuits


def generate_telemetry_dataset(
    circuits: List[CircuitLink],
    days: int = 30,
    interval_minutes: int = 5,
    seed: int = 42
) -> pd.DataFrame:
    """
    Generates high-density time-series traffic samples.
    30 days of 5-minute intervals = 8,640 samples per link.
    Simulates diurnal enterprise cycles, weekend drops, and stochastic backup spikes.
    """
    rng = np.random.default_rng(seed)
    samples_per_day = (24 * 60) // interval_minutes
    total_intervals = days * samples_per_day
    base_epoch = 1735689600  # 2025-01-01 00:00:00 UTC

    rows = []
    # Diurnal cycle curve (hour 0-24)
    hours = np.linspace(0, 24 * days, total_intervals, endpoint=False) % 24
    diurnal_pattern = 0.35 + 0.55 * np.maximum(0, np.sin((hours - 7) * np.pi / 16))

    for circuit in circuits:
        cir = circuit.committed_information_rate_mbps
        pir = circuit.peak_information_rate_mbps

        # Base load varying around 60% of CIR
        nominal_mean = cir * 0.65
        noise = rng.normal(0, cir * 0.08, total_intervals)
        
        # Periodic heavy backup burst spikes (probability 2% per interval)
        spikes = rng.choice([0.0, 1.0], size=total_intervals, p=[0.982, 0.018]) * rng.uniform(cir * 0.4, (pir - nominal_mean) * 0.9, total_intervals)

        aggregate = np.clip((nominal_mean * diurnal_pattern) + noise + spikes, a_min=cir * 0.1, a_max=pir)
        egress = aggregate * rng.uniform(0.55, 0.68, total_intervals)
        ingress = aggregate - egress

        epochs = base_epoch + (np.arange(total_intervals) * (interval_minutes * 60))

        for ep, agg, eg, ing in zip(epochs, aggregate, egress, ingress):
            rows.append({
                "timestamp_epoch": int(ep),
                "link_id": circuit.link_id,
                "carrier_name": circuit.carrier_name,
                "pop_location": circuit.pop_location,
                "aggregate_mbps": float(np.round(agg, 2)),
                "egress_mbps": float(np.round(eg, 2)),
                "ingress_mbps": float(np.round(ing, 2)),
                "cir_mbps": cir,
                "pir_mbps": pir
            })

    return pd.DataFrame(rows)


def run_generator_pipeline(
    output_path: str = "data/telemetry_dataset.csv.gz",
    seed: int = 42
) -> Tuple[List[CircuitLink], pd.DataFrame]:
    """Orchestrates circuit creation and telemetry persistence."""
    start_time = time.time()
    circuits = generate_reference_circuits(seed=seed)
    df = generate_telemetry_dataset(circuits=circuits, days=30, seed=seed)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    if output_path.endswith(".parquet"):
        try:
            df.to_parquet(output_path, index=False)
        except Exception:
            # Fallback to compressed CSV if pyarrow is unavailable
            fallback_csv = output_path.replace(".parquet", ".csv.gz")
            df.to_csv(fallback_csv, compression="gzip", index=False)
            output_path = fallback_csv
    elif output_path.endswith(".gz") or output_path.endswith(".csv"):
        df.to_csv(output_path, compression="gzip" if output_path.endswith(".gz") else None, index=False)
    else:
        df.to_csv(output_path, index=False)

    elapsed = time.time() - start_time
    print(f"[Data Generator] Successfully generated {len(df):,} telemetry samples for {len(circuits)} circuits in {elapsed:.2f}s -> {output_path}")

    return circuits, df


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="AegisTransit Telemetry Dataset Generator.")
    parser.add_argument("--output", type=str, default="data/telemetry_dataset.csv.gz")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    run_generator_pipeline(output_path=args.output, seed=args.seed)