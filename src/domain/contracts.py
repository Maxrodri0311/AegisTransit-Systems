"""
src/domain/contracts.py - Inversion of Dependencies (DIP) Protocols.
All analytical and delivery services depend strictly on these abstract interfaces.
"""

from typing import Protocol, List, Dict, Any, Optional
import pandas as pd
from .entities import (
    CircuitLink,
    TrafficSample,
    OptimizationResult,
    ContractSurvivalMetrics,
)


class TelemetryStorageProtocol(Protocol):
    """Abstract contract for columnar telemetry ingestion and queries."""
    def save_links(self, links: List[CircuitLink]) -> None: ...
    def save_samples(self, samples: List[TrafficSample]) -> None: ...
    def get_links(self) -> List[CircuitLink]: ...
    def get_samples_df(self) -> pd.DataFrame: ...
    def compute_95th_percentile(self, link_id: str) -> float: ...


class LinearCostOptimizerProtocol(Protocol):
    """Abstract algorithmic decision engine for multi-carrier transit load balancing."""
    def solve(
        self,
        links: List[CircuitLink],
        target_demand_mbps: float,
        latency_budget_ms: Optional[float] = None
    ) -> OptimizationResult: ...


class ContractSurvivalAnalyzerProtocol(Protocol):
    """Abstract estimator for contract survival curves and hazard rates."""
    def estimate_survival(self, links: List[CircuitLink]) -> List[ContractSurvivalMetrics]: ...


class SinkRendererProtocol(Protocol):
    """Abstract delivery contract for CLI/TUI and reporting output."""
    def render(
        self,
        optimization: OptimizationResult,
        survival: List[ContractSurvivalMetrics]
    ) -> Any: ...