"""
src/interface.py - Rich Terminal User Interface (CLI_TUI Paradigm).
Enterprise Executive Dashboard for CommandLink SD-WAN Transit Cost Optimization & Contract Survival.
Strictly decoupled under SinkRendererProtocol.
"""

import sys
import json
import argparse
from pathlib import Path
from typing import List, Optional

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.layout import Layout
from rich.text import Text
from rich import box

# Bootstrap path
project_root = str(Path(__file__).resolve().parent.parent)
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from src.domain.entities import OptimizationResult, ContractSurvivalMetrics
from src.core_engine import create_engine

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

console = Console(highlight=False)


class RichTerminalRenderer:
    """Concrete delivery sink for rich CLI/TUI executive visualization."""
    def __init__(self, console_instance: Optional[Console] = None):
        self.console = console_instance or console

    def render(
        self,
        optimization: OptimizationResult,
        survival: List[ContractSurvivalMetrics]
    ) -> None:
        # Header Banner
        header_text = Text()
        header_text.append("COMMANDLINK ", style="bold cyan")
        header_text.append("| SD-WAN TRANSIT OPTIMIZER & SURVIVAL ENGINE\n", style="bold white")
        header_text.append("95th-Percentile Burstable Billing Arbitrage & Contract Hazard Analytics (GP-260)", style="dim italic")

        self.console.print(Panel(header_text, border_style="cyan", box=box.ROUNDED))

        # KPI Summary Cards
        kpi_table = Table(box=box.SIMPLE, show_header=False, expand=True)
        kpi_table.add_column("K1", justify="center")
        kpi_table.add_column("K2", justify="center")
        kpi_table.add_column("K3", justify="center")
        kpi_table.add_column("K4", justify="center")

        kpi_table.add_row(
            f"[dim]Managed Demand[/dim]\n[bold green]{optimization.total_managed_demand_mbps:,.0f} Mbps[/bold green]",
            f"[dim]Baseline Cost[/dim]\n[bold yellow]${optimization.unmanaged_baseline_cost_usd:,.2f}[/bold yellow]",
            f"[dim]Optimized Cost[/dim]\n[bold cyan]${optimization.total_optimized_cost_usd:,.2f}[/bold cyan]",
            f"[dim]Monthly Net Savings[/dim]\n[bold green]+${optimization.net_monthly_savings_usd:,.2f} ({optimization.savings_percentage}%)[/bold green]"
        )
        self.console.print(Panel(kpi_table, title="[bold]>> EXECUTIVE FINANCIAL SUMMARY[/bold]", border_style="green", box=box.ROUNDED))

        # Table 1: Carrier Allocation Strategy
        alloc_table = Table(
            title="[bold]>> MULTI-CARRIER TRANSIT ALLOCATION MATRIX (LINEAR PROGRAMMING)[/bold]",
            box=box.HEAVY_EDGE,
            header_style="bold magenta"
        )
        alloc_table.add_column("Circuit ID", style="cyan", no_wrap=True)
        alloc_table.add_column("Carrier Name", style="white")
        alloc_table.add_column("Allocated Load", justify="right", style="bold green")
        alloc_table.add_column("Effective 95th", justify="right", style="cyan")
        alloc_table.add_column("Burst Status", justify="center")
        alloc_table.add_column("Monthly Cost", justify="right", style="bold yellow")
        alloc_table.add_column("Variance Savings", justify="right", style="green")

        for alloc in optimization.carrier_allocations:
            burst_badge = "[bold red]BURSTING[/bold red]" if alloc.is_bursting else "[bold green]COMMITTED[/bold green]"
            alloc_table.add_row(
                alloc.link_id,
                alloc.carrier_name,
                f"{alloc.allocated_mbps:,.2f} Mbps",
                f"{alloc.effective_95th_mbps:,.2f} Mbps",
                burst_badge,
                f"${alloc.monthly_cost_usd:,.2f}",
                f"+${alloc.savings_vs_unmanaged_usd:,.2f}"
            )
        self.console.print(alloc_table)

        # Table 2: Contract Survival & Hazard Radar
        survival_table = Table(
            title="[bold]>> CARRIER CONTRACT SURVIVAL & CHURN RISK (KAPLAN-MEIER / COX PH)[/bold]",
            box=box.HEAVY_EDGE,
            header_style="bold blue"
        )
        survival_table.add_column("Circuit ID", style="cyan", no_wrap=True)
        survival_table.add_column("Carrier", style="white")
        survival_table.add_column("Tenure", justify="center")
        survival_table.add_column("Survival S(t)", justify="right", style="cyan")
        survival_table.add_column("Hazard Ratio", justify="right", style="bold")
        survival_table.add_column("Urgency", justify="center")
        survival_table.add_column("Strategic Action", style="italic")

        for m in survival:
            urgency_style = {
                "CRITICAL": "[bold white on red] CRITICAL [/bold white on red]",
                "HIGH": "[bold black on yellow] HIGH [/bold black on yellow]",
                "MEDIUM": "[bold cyan] MEDIUM [/bold cyan]",
                "LOW": "[green] LOW [/green]"
            }.get(m.renegotiation_urgency, m.renegotiation_urgency)

            survival_table.add_row(
                m.link_id,
                m.carrier_name,
                f"{m.tenure_months} mos",
                f"{m.survival_probability * 100:.1f}%",
                f"{m.hazard_ratio:.2f}x",
                urgency_style,
                m.suggested_action
            )
        self.console.print(survival_table)
        self.console.print(f"[dim]Solver Engine: SciPy HiGHS | Sub-150ms Telemetry Validation: {optimization.execution_time_ms} ms[/dim]\n")


def run_cli():
    parser = argparse.ArgumentParser(description="CommandLink SD-WAN Transit Cost Optimization Dashboard.")
    parser.add_argument("--demand", type=float, default=9500.0, help="Aggregate traffic demand in Mbps to balance.")
    parser.add_argument("--latency", type=float, default=22.0, help="Nominal SLA latency constraint budget in ms.")
    parser.add_argument("--export-json", type=str, default="", help="Optional filepath to dump output as JSON.")
    args = parser.parse_args()

    engine = create_engine()
    results = engine.run_optimization_cycle(
        target_demand_mbps=args.demand,
        latency_budget_ms=args.latency
    )

    renderer = RichTerminalRenderer(console)
    renderer.render(results["optimization"], results["survival"])

    if args.export_json:
        payload = {
            "optimization": results["optimization"].model_dump(),
            "survival": [s.model_dump() for s in results["survival"]]
        }
        with open(args.export_json, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        console.print(f"[bold green]✔ Optimization report exported to: {args.export_json}[/bold green]")


if __name__ == "__main__":
    run_cli()