"""Quality gates checked against both SQL eligibility and independent rule assertions."""

from __future__ import annotations

import sqlite3

from .config import CampaignConfig
from .pipeline import stable_bucket


def run_quality_checks(con: sqlite3.Connection, cfg: CampaignConfig, steps: list[dict]) -> dict:
    start, eligible = steps[0]["remaining"], steps[-1]["remaining"]
    allocations = [dict(r) for r in con.execute("SELECT * FROM allocations")]
    by_segment = {segment: {r["customer_id"] for r in allocations if r["segment"] == segment}
                  for segment in ("TEST", "CONTROL")}
    allocated_ids = {r["customer_id"] for r in allocations}
    eligible_ids = {r["customer_id"] for r in con.execute("SELECT customer_id FROM eligible_audience")}
    expected_cells = {(p, s): f"{cfg.campaign_id}_{p}_{s}" for p in cfg.eligible_products for s in ("TEST", "CONTROL")}
    controls_expected = {r["customer_id"] for r in allocations
                         if stable_bucket(cfg.campaign_id, r["customer_id"]) < cfg.holdout_percent * 100}
    actual_control = by_segment["CONTROL"]
    independently_eligible = {
        r["customer_id"] for r in con.execute("SELECT * FROM customers")
        if (r["is_active"] == 1 and r["product_type"] in cfg.eligible_products and
            r["country"] in cfg.allowed_countries and r["marketing_opt_in"] == 1 and
            r["has_email"] == 1 and bool(r["email"].strip()) and r["is_employee"] == 0 and
            r["is_legacy_subscriber"] == 0 and r["is_promotional_exclusion"] == 0 and
            r["contacts_30d"] < cfg.max_contacts_30d and
            r["account_age_days"] >= cfg.min_account_age_days)
    }
    monotonic = all(a["remaining"] >= b["remaining"] >= 0 for a, b in zip(steps, steps[1:]))
    holdout_actual_pct = 100.0 * len(actual_control) / eligible if eligible else 0.0
    # Distribution is stochastic-looking even though assignment is deterministic.
    # For small populations, report the percentage without failing on normal sampling variance.
    checks = [
        ("Waterfall is monotonic", monotonic, "No step can gain customers"),
        ("Waterfall exclusion reconciliation", sum(s["excluded_at_step"] for s in steps) == start-eligible,
         "Step exclusions equal starting population minus eligible population"),
        ("Allocation coverage", allocated_ids == eligible_ids and len(allocations) == eligible,
         "Exactly one row per eligible customer and no ineligible allocations"),
        ("Independent eligibility audit", eligible_ids == independently_eligible,
         "SQL eligibility agrees with independent Python rule evaluation"),
        ("Distinct test/control cohorts", not (by_segment["TEST"] & actual_control),
         "No customer appears in both cohorts"),
        ("Deterministic assignment", actual_control == controls_expected and all(
            r["bucket"] == stable_bucket(cfg.campaign_id, r["customer_id"]) for r in allocations),
         "Recomputed hash buckets reproduce all control assignments"),
        ("Cell code and product integrity", all(
            r["cell_code"] == expected_cells.get((r["product_type"], r["segment"])) and
            r["cell_name"] == f"{r['product_type']} {r['segment'].title()}" and
            r["product_type"] == con.execute("SELECT product_type FROM customers WHERE customer_id=?", (r["customer_id"],)).fetchone()[0]
            for r in allocations),
         "Cell metadata matches campaign, product, segment, and source"),
        ("Holdout allocation within 5 percentage points", eligible < 100 or
         abs(holdout_actual_pct - cfg.holdout_percent) <= 5,
         f"Configured {cfg.holdout_percent}% vs actual {holdout_actual_pct:.2f}% (small n < 100 exempt)"),
    ]
    test = len(by_segment["TEST"])
    control = len(actual_control)
    return {
        "campaign_id": cfg.campaign_id,
        "passed": all(ok for _, ok, _ in checks),
        "metrics": {
            "starting": start, "eligible": eligible, "test": test, "control": control,
            "holdout_percent_configured": cfg.holdout_percent,
            "holdout_percent_actual": round(holdout_actual_pct, 2),
        },
        "checks": [{"name": name, "passed": ok, "detail": detail} for name, ok, detail in checks],
    }
