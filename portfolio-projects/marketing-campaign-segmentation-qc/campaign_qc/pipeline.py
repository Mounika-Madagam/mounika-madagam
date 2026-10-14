"""Local SQLite campaign segmentation pipeline and deterministic control allocation."""

from __future__ import annotations

import csv
import hashlib
import json
import sqlite3
from pathlib import Path
from typing import Iterable

from .config import CampaignConfig
from .generate import FIELDS, generate_customers

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DB_FIELDS = tuple(FIELDS)
NUMERIC_FIELDS = {
    "is_active", "marketing_opt_in", "has_email", "is_employee",
    "is_legacy_subscriber", "is_promotional_exclusion", "contacts_30d", "account_age_days",
}


def stable_bucket(campaign_id: str, customer_id: str) -> int:
    """Stable [0,9999] assignment independent of CSV input ordering and Python hash randomization."""
    data = f"{campaign_id}|{customer_id}".encode("utf-8")
    return int.from_bytes(hashlib.sha256(data).digest()[:8], "big") % 10_000


def connect_database(path: Path, cfg: CampaignConfig) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()  # Fresh reproducible output; never modify an existing source database.
    con = sqlite3.connect(path)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript((PROJECT_ROOT / "sql" / "schema.sql").read_text(encoding="utf-8"))
    con.executemany("INSERT INTO campaign_settings(name, value) VALUES (?, ?)", [
        ("campaign_id", cfg.campaign_id),
        ("max_contacts_30d", str(cfg.max_contacts_30d)),
        ("min_account_age_days", str(cfg.min_account_age_days)),
        ("holdout_percent", str(cfg.holdout_percent)),
    ])
    con.executemany("INSERT INTO allowed_products(product_type) VALUES (?)", [(x,) for x in cfg.eligible_products])
    con.executemany("INSERT INTO allowed_countries(country) VALUES (?)", [(x,) for x in cfg.allowed_countries])
    con.executescript((PROJECT_ROOT / "sql" / "stages.sql").read_text(encoding="utf-8"))
    con.commit()
    return con


def import_customers(con: sqlite3.Connection, csv_path: Path) -> int:
    with csv_path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != FIELDS:
            raise ValueError(f"CSV headers must match exactly: {', '.join(FIELDS)}")
        rows = []
        for i, row in enumerate(reader, start=2):
            try:
                if not row["customer_id"] or not row["product_type"] or not row["country"]:
                    raise ValueError("missing required identifier or category")
                record = tuple(int(row[k]) if k in NUMERIC_FIELDS else row[k] for k in DB_FIELDS)
                rows.append(record)
            except (TypeError, ValueError) as exc:
                raise ValueError(f"Invalid CSV row {i}: {exc}") from exc
    if not rows:
        raise ValueError("Input CSV must have at least one customer")
    cols = ", ".join(DB_FIELDS)
    marks = ", ".join(["?"] * len(DB_FIELDS))
    try:
        con.executemany(f"INSERT INTO customers ({cols}) VALUES ({marks})", rows)
        con.commit()
    except sqlite3.IntegrityError as exc:
        con.rollback()
        raise ValueError(f"Customer input violates uniqueness or validity constraints: {exc}") from exc
    return len(rows)


def allocate(con: sqlite3.Connection, cfg: CampaignConfig) -> int:
    """Assign every eligible customer to exactly one test or control cohort."""
    customers = con.execute("SELECT customer_id, product_type FROM eligible_audience ORDER BY customer_id").fetchall()
    records = []
    for customer in customers:
        bucket = stable_bucket(cfg.campaign_id, customer["customer_id"])
        segment = "CONTROL" if bucket < cfg.holdout_percent * 100 else "TEST"
        product = customer["product_type"]
        cell_name = f"{product} {segment.title()}"
        cell_code = f"{cfg.campaign_id}_{product}_{segment}"
        records.append((customer["customer_id"], product, segment, bucket, cell_name, cell_code))
    con.executemany("""INSERT INTO allocations
        (customer_id, product_type, segment, bucket, cell_name, cell_code)
        VALUES (?, ?, ?, ?, ?, ?)""", records)
    con.commit()
    return len(records)


def waterfall_rows(con: sqlite3.Connection) -> list[dict]:
    current = [dict(row) for row in con.execute("SELECT step, stage, remaining FROM waterfall ORDER BY step")]
    previous = current[0]["remaining"] if current else 0
    for item in current:
        item["excluded_at_step"] = previous - item["remaining"]
        previous = item["remaining"]
    return current


def write_csv(path: Path, fieldnames: Iterable[str], rows: Iterable[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(fieldnames))
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def export_results(con: sqlite3.Connection, output: Path, cfg: CampaignConfig) -> dict:
    from .qc import run_quality_checks

    steps = waterfall_rows(con)
    write_csv(output / "waterfall.csv", ["step", "stage", "remaining", "excluded_at_step"], steps)
    test_cols = ["customer_id", "product_type", "email", "cell_name", "cell_code"]
    control_cols = ["customer_id", "product_type", "cell_name", "cell_code"]
    for segment, file_name, cols in (
        ("TEST", "sendable_test.csv", test_cols),
        ("CONTROL", "holdout_control.csv", control_cols),
    ):
        query = f"""SELECT {', '.join('a.' + col if col != 'email' else 'c.email' for col in cols)}
            FROM allocations a JOIN customers c USING (customer_id)
            WHERE a.segment = ? ORDER BY a.customer_id"""
        write_csv(output / "exports" / file_name, cols,
                  (dict(row) for row in con.execute(query, (segment,))))
    result = run_quality_checks(con, cfg, steps)
    (output / "qc_report.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    lines = [
        "# Campaign quality-control report", "",
        f"Campaign: **{cfg.campaign_id}**", "",
        f"- Starting customers: **{result['metrics']['starting']}**",
        f"- Eligible customers: **{result['metrics']['eligible']}**",
        f"- Test: **{result['metrics']['test']}**",
        f"- Control (non-sendable): **{result['metrics']['control']}**",
        f"- Overall status: **{'PASS' if result['passed'] else 'FAIL'}**", "",
        "## Sequential waterfall", "",
        "| Step | Rule | Remaining | Excluded at step |", "| ---: | --- | ---: | ---: |",
    ]
    lines.extend(f"| {row['step']} | {row['stage']} | {row['remaining']} | {row['excluded_at_step']} |" for row in steps)
    lines.extend(["", "## Automated quality gates", "", "| Check | Result | Details |", "| --- | --- | --- |"])
    lines.extend(f"| {x['name']} | {'PASS' if x['passed'] else 'FAIL'} | {x['detail']} |" for x in result["checks"])
    lines.extend(["", "**Note:** Test and control counts follow a stable hash allocation; the split is approximately, not exactly, the configured percentage. All customers are synthetic.", ""])
    (output / "qc_report.md").write_text("\n".join(lines), encoding="utf-8")
    return result


def run_pipeline(cfg: CampaignConfig, output: Path, *, input_csv: Path | None = None,
                 count: int = 3000, seed: int = 42) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    if input_csv is None:
        input_csv = generate_customers(output / "input" / "synthetic_customers.csv", count=count, seed=seed)
    con = connect_database(output / "campaign.sqlite3", cfg)
    try:
        import_customers(con, input_csv)
        allocate(con, cfg)
        result = export_results(con, output, cfg)
    finally:
        con.close()
    return result
