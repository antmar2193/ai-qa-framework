"""CLI entry point for the QA framework."""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

import click
from rich.console import Console
from rich.logging import RichHandler
from rich.table import Table

from src.models.config import FrameworkConfig
from src.models.test_plan import TestPlan
from src.orchestrator import Orchestrator
from src.projects.exceptions import ProjectAlreadyExistsError, ProjectNotFoundError
from src.projects.registry import ProjectRegistry
from src.projects.resolver import resolve_config


def _get_registry() -> ProjectRegistry:
    return ProjectRegistry()

console = Console()


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(message)s",
        datefmt="[%X]",
        handlers=[RichHandler(console=console, rich_tracebacks=True)],
    )


@click.group()
@click.option("--verbose", "-v", is_flag=True, help="Enable debug logging")
def cli(verbose: bool) -> None:
    """AI-Driven Autonomous Website QA Framework"""
    setup_logging(verbose)


@cli.command()
@click.option("--config", "-c", default="qa-config.json", help="Config file path")
@click.option("--project", "-p", default=None, help="Project name")
def run(config: str, project: str) -> None:
    """Run the full QA pipeline: crawl → plan → execute → report."""
    cfg, runs_dir = resolve_config(project, config, _get_registry())
    orchestrator = Orchestrator(cfg, runs_dir=runs_dir)
    results = orchestrator.run_full_pipeline()

    console.print("\n[bold green]Pipeline Complete[/bold green]")
    table = Table(title="Results Summary")
    table.add_column("Metric", style="bold")
    table.add_column("Value")
    table.add_row("Run ID", results["run_id"])
    table.add_row("Duration", f"{results['duration']}s")
    table.add_row("Total Tests", str(results["results"]["total"]))
    table.add_row("Passed", f"[green]{results['results']['passed']}[/green]")
    table.add_row("Failed", f"[red]{results['results']['failed']}[/red]")
    table.add_row("Skipped", f"[yellow]{results['results']['skipped']}[/yellow]")
    table.add_row("Errors", f"[red]{results['results']['errors']}[/red]")
    table.add_row("Coverage", f"{results['coverage']['overall']:.0%}")
    console.print(table)

    for fmt, path in results["reports"].items():
        console.print(f"  {fmt.upper()} report: [blue]{path}[/blue]")


@cli.command()
@click.option("--config", "-c", default="qa-config.json", help="Config file path")
@click.option("--project", "-p", default=None, help="Project name")
def crawl(config: str, project: str) -> None:
    """Crawl the target site and build a site model."""
    cfg, runs_dir = resolve_config(project, config, _get_registry())
    orchestrator = Orchestrator(cfg, runs_dir=runs_dir)
    site_model = orchestrator.run_crawl_only()
    console.print(f"[green]Crawl complete:[/green] {len(site_model.pages)} pages discovered")


@cli.command()
@click.option("--config", "-c", default="qa-config.json", help="Config file path")
@click.option("--project", "-p", default=None, help="Project name")
def plan(config: str, project: str) -> None:
    """Generate a test plan from the existing site model."""
    cfg, runs_dir = resolve_config(project, config, _get_registry())
    orchestrator = Orchestrator(cfg, runs_dir=runs_dir)
    try:
        test_plan = orchestrator.run_plan_only()
        console.print(f"[green]Plan generated:[/green] {len(test_plan.test_cases)} test cases")
    except FileNotFoundError as e:
        console.print(f"[red]{e}[/red]")
        sys.exit(1)


@cli.command()
@click.option("--plan-file", required=True, help="Path to test plan JSON")
@click.option("--config", "-c", default="qa-config.json", help="Config file path")
@click.option("--project", "-p", default=None, help="Project name")
def execute(plan_file: str, config: str, project: str) -> None:
    """Execute a saved test plan."""
    cfg, runs_dir = resolve_config(project, config, _get_registry())
    with open(plan_file) as f:
        plan_data = json.load(f)
    test_plan = TestPlan(**plan_data)

    orchestrator = Orchestrator(cfg, runs_dir=runs_dir)
    result = orchestrator.run_execute_only(test_plan)
    console.print(
        f"[green]Execution complete:[/green] {result.passed} passed, "
        f"{result.failed} failed, {result.skipped} skipped"
    )


@cli.command()
@click.option("--gaps", is_flag=True, help="Show coverage gaps")
@click.option("--reset", is_flag=True, help="Reset coverage registry")
@click.option("--config", "-c", default="qa-config.json", help="Config file path")
@click.option("--project", "-p", default=None, help="Project name")
def coverage(gaps: bool, reset: bool, config: str, project: str) -> None:
    """View or manage coverage data."""
    cfg, runs_dir = resolve_config(project, config, _get_registry())
    orchestrator = Orchestrator(cfg, runs_dir=runs_dir)

    if reset:
        orchestrator.reset_coverage()
        console.print("[green]Coverage registry reset[/green]")
        return

    if gaps:
        try:
            gap_text = orchestrator.get_coverage_gaps()
            console.print(gap_text)
        except FileNotFoundError:
            console.print("[yellow]No site model found. Run 'qa-framework crawl' first.[/yellow]")
        return

    summary = orchestrator.get_coverage_summary()
    console.print(summary)


@cli.command()
@click.option("--target", "-t", prompt="Target URL", help="Website URL to test")
def init(target: str) -> None:
    """Create a default configuration file."""
    config_path = Path("qa-config.json")
    if config_path.exists():
        if not click.confirm("qa-config.json already exists. Overwrite?"):
            return

    cfg = FrameworkConfig(target_url=target)
    cfg.save(config_path)
    console.print(f"[green]Created {config_path}[/green]")
    console.print("\nYou can now customize this file and run:")
    console.print("  [blue]qa-framework run[/blue]")
    console.print("\nOptional: Add hints to guide the AI planner:")
    console.print('  [blue]qa-framework hint add "The checkout flow is critical"[/blue]')


@cli.group()
def hint() -> None:
    """Manage user hints for the AI planner."""
    pass


@hint.command("add")
@click.argument("text")
@click.option("--config", "-c", default="qa-config.json", help="Config file path")
def hint_add(text: str, config: str) -> None:
    """Add a hint to the configuration."""
    cfg = FrameworkConfig.load(config)
    cfg.hints.append(text)
    cfg.save(config)
    console.print(f"[green]Added hint:[/green] {text}")


@hint.command("list")
@click.option("--config", "-c", default="qa-config.json", help="Config file path")
def hint_list(config: str) -> None:
    """List all current hints."""
    cfg = FrameworkConfig.load(config)
    if not cfg.hints:
        console.print("[yellow]No hints configured[/yellow]")
        return
    for i, h in enumerate(cfg.hints, 1):
        console.print(f"  {i}. {h}")


@hint.command("clear")
@click.option("--config", "-c", default="qa-config.json", help="Config file path")
def hint_clear(config: str) -> None:
    """Remove all hints."""
    cfg = FrameworkConfig.load(config)
    cfg.hints = []
    cfg.save(config)
    console.print("[green]All hints cleared[/green]")


@cli.group()
def project() -> None:
    """Manage QA projects."""
    pass


@project.command("create")
@click.option("--name", "-n", required=True, help="Project name")
@click.option("--target", "-t", required=True, help="Target URL")
def project_create(name: str, target: str) -> None:
    """Create a new QA project."""
    registry = _get_registry()
    try:
        config = registry.create(name, target)
        registry.set_active(name)
        console.print(f"[green]Created project '{name}'[/green]")
        console.print(f"  Config: [blue]{registry.project_dir(name) / 'config.json'}[/blue]")
        console.print(f"  Target: {config.target_url}")
        console.print(f"\nProject '{name}' set as active. Run: [blue]qa-framework run[/blue]")
    except ProjectAlreadyExistsError as e:
        console.print(f"[red]{e}[/red]")
        raise SystemExit(1)


@project.command("import")
@click.option("--name", "-n", required=True, help="Project name")
@click.option("--config", "-c", default="qa-config.json", help="Config file to import")
def project_import(name: str, config: str) -> None:
    """Import an existing qa-config.json as a named project."""
    registry = _get_registry()
    config_path = Path(config)
    if not config_path.exists():
        console.print(f"[red]Config file not found: {config_path}[/red]")
        raise SystemExit(1)
    if registry.exists(name):
        console.print(f"[red]Project '{name}' already exists.[/red]")
        raise SystemExit(1)
    try:
        cfg = FrameworkConfig.load(config_path)
        project_dir = registry.project_dir(name)
        (project_dir / "runs").mkdir(parents=True, exist_ok=True)
        (project_dir / "qa-reports").mkdir(parents=True, exist_ok=True)
        cfg.report_output_dir = str(project_dir / "qa-reports")
        cfg.save(project_dir / "config.json")
        registry.set_active(name)
        console.print(f"[green]Imported '{config_path}' as project '{name}'[/green]")
        console.print(f"  Config: [blue]{project_dir / 'config.json'}[/blue]")
        console.print(f"  Target: {cfg.target_url}")
        console.print(f"\nProject '{name}' set as active.")
    except Exception as e:
        console.print(f"[red]Import failed: {e}[/red]")
        raise SystemExit(1)


@project.command("use")
@click.argument("name")
def project_use(name: str) -> None:
    """Set the active project."""
    registry = _get_registry()
    try:
        registry.set_active(name)
        console.print(f"[green]Active project set to '{name}'[/green]")
    except ProjectNotFoundError as e:
        console.print(f"[red]{e}[/red]")
        raise SystemExit(1)


@project.command("delete")
@click.argument("name")
def project_delete(name: str) -> None:
    """Delete a project and all its run history."""
    registry = _get_registry()
    if not registry.exists(name):
        console.print(f"[red]Project '{name}' not found.[/red]")
        raise SystemExit(1)
    if not click.confirm(f"Delete project '{name}' and all its run history?"):
        console.print("Aborted.")
        return
    registry.delete(name)
    console.print(f"[green]Project '{name}' deleted.[/green]")


@project.command("list")
def project_list() -> None:
    """List all configured projects."""
    registry = _get_registry()
    projects = registry.list()
    if not projects:
        console.print(
            "[yellow]No projects configured.[/yellow] "
            "Run: [blue]qa-framework project create --name <n> --target <url>[/blue]"
        )
        return
    table = Table(title="QA Projects")
    table.add_column("Name", style="bold")
    table.add_column("Target URL")
    table.add_column("Last Run")
    table.add_column("Passed", justify="right")
    table.add_column("Failed", justify="right")
    table.add_column("Active", justify="center")
    for p in projects:
        last_run = p.last_run_date[:10] if p.last_run_date else "—"
        passed = str(p.last_run_stats["passed"]) if p.last_run_stats else "—"
        failed = str(p.last_run_stats["failed"]) if p.last_run_stats else "—"
        active = "[green]✓[/green]" if p.active else ""
        table.add_row(p.name, p.target_url, last_run, passed, failed, active)
    console.print(table)


@project.command("history")
@click.argument("name")
@click.option("--last", default=10, show_default=True, help="Number of runs to show")
def project_history(name: str, last: int) -> None:
    """Show run history for a project."""
    registry = _get_registry()
    try:
        runs = registry.list_runs(name, limit=last)
    except ProjectNotFoundError as e:
        console.print(f"[red]{e}[/red]")
        raise SystemExit(1)
    if not runs:
        console.print(f"[yellow]No runs yet for '{name}'.[/yellow]")
        return
    table = Table(title=f"Run history — {name}")
    table.add_column("Run ID")
    table.add_column("Date")
    table.add_column("Duration")
    table.add_column("Total", justify="right")
    table.add_column("Passed", justify="right", style="green")
    table.add_column("Failed", justify="right", style="red")
    for r in runs:
        date = (r.get("completed_at") or "")[:16].replace("T", " ")
        duration = f"{r.get('duration_seconds', 0):.0f}s"
        table.add_row(
            r.get("run_id", "—"),
            date or "—",
            duration,
            str(r.get("total_tests", 0)),
            str(r.get("passed", 0)),
            str(r.get("failed", 0)),
        )
    console.print(table)


@cli.command()
@click.option("--project", "-p", default=None, help="Project name")
@click.option("--run-id", required=True, help="Run ID to export")
@click.option("--output", "-o", default=None, help="Output file path (default: report_<run_id>.xlsx)")
def export(project: str, run_id: str, output: str) -> None:
    """Export a run result to Excel (.xlsx)."""
    from src.web.excel_export import generate_xlsx

    cfg, runs_dir = resolve_config(project, "qa-config.json", _get_registry())
    registry = _get_registry()

    # Resolve runs directory
    if project:
        runs_base = registry.runs_dir(project)
    elif runs_dir:
        runs_base = runs_dir
    else:
        runs_base = Path("runs")

    result_path = runs_base / run_id / "run_result.json"
    if not result_path.exists():
        console.print(f"[red]Run '{run_id}' not found at {result_path}[/red]")
        sys.exit(1)

    from src.models.test_result import RunResult
    run_result = RunResult.model_validate_json(result_path.read_text())
    xlsx_bytes = generate_xlsx(run_result)

    out_path = Path(output) if output else Path(f"report_{run_id}.xlsx")
    out_path.write_bytes(xlsx_bytes)
    console.print(f"[green]Excel report saved:[/green] [blue]{out_path}[/blue]")


@cli.command()
@click.option("--port", default=8000, show_default=True, help="Port to listen on")
def serve(port: int) -> None:
    """Start the web UI server."""
    import uvicorn

    from src.web.app import create_app

    app = create_app(_get_registry())
    console.print(
        f"[green]QA Framework Web UI:[/green] [blue]http://localhost:{port}[/blue]"
    )
    uvicorn.run(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    cli()
