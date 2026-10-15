"""
Domain package for CommandLink Cost Optimization Engine.
"""

from .entities import (
    CircuitLink,
    TrafficSample,
    CarrierAllocation,
    OptimizationResult,
    ContractSurvivalMetrics,
)
from .contracts import (
    TelemetryStorageProtocol,
    LinearCostOptimizerProtocol,
    ContractSurvivalAnalyzerProtocol,
    SinkRendererProtocol,
)

__all__ = [
    "CircuitLink",
    "TrafficSample",
    "CarrierAllocation",
    "OptimizationResult",
    "ContractSurvivalMetrics",
    "TelemetryStorageProtocol",
    "LinearCostOptimizerProtocol",
    "ContractSurvivalAnalyzerProtocol",
    "SinkRendererProtocol",
]
