#!/usr/bin/env bash
set -e

echo "================================================================================"
echo "  commandlink-finance-linear-optimization-engine"
echo "  Automated Linux/macOS Execution & Benchmark Runner"
echo "================================================================================"
echo ""

echo "[1/4] Generating Calibrated Stochastic Telemetry..."
python src/data_generator.py --records 50000

echo ""
echo "[2/4] Executing Executive Delivery Interface..."
python src/interface.py

echo ""
echo "[3/4] Running Automated Pytest Invariant Suite..."
python -m pytest tests/ -v

echo ""
echo "[4/4] Executing Latency & Memory SLA Profiler..."
python tests/benchmark.py

echo ""
echo "================================================================================"
echo "  [SUCCESS] All Mathematical Invariants and Latency SLAs Verified!"
echo "================================================================================"