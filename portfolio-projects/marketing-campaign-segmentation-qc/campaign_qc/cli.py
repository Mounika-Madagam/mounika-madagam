"""Command line interface. No third-party dependencies required."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .config import load_config
from .generate import generate_customers
from .pipeline import run_pipeline


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Synthetic marketing segmentation & QC")
    sub = parser.add_subparsers(dest="command", required=True)
    make = sub.add_parser("generate", help="Create deterministic, entirely synthetic customer data")
    make.add_argument("--output", type=Path, default=Path("out/input/synthetic_customers.csv"))
    make.add_argument("--count", type=int, default=3000)
    make.add_argument("--seed", type=int, default=42)
    run = sub.add_parser("run", help="Build eligible audience, assign cohorts, and produce QC reports")
    run.add_argument("--config", type=Path, default=Path("config/demo_campaign.json"))
    run.add_argument("--output", type=Path, default=Path("out"))
    run.add_argument("--input", dest="input_csv", type=Path, default=None,
                     help="Optional local CSV matching generator schema; defaults to synthetic data")
    run.add_argument("--count", type=int, default=3000)
    run.add_argument("--seed", type=int, default=42)
    args = parser.parse_args(argv)
    try:
        if args.command == "generate":
            print(f"Generated synthetic data: {generate_customers(args.output, args.count, args.seed)}")
            return 0
        cfg = load_config(args.config)
        result = run_pipeline(cfg, args.output, input_csv=args.input_csv,
                              count=args.count, seed=args.seed)
        print(json.dumps({"passed": result["passed"], **result["metrics"]}, indent=2))
        print(f"Reports and exports: {args.output.resolve()}")
        return 0 if result["passed"] else 2
    except (OSError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
