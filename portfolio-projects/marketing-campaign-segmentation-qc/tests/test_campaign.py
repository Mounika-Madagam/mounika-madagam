"""Regression, boundary, tampering, and reproducibility tests."""

from __future__ import annotations

import csv
import json
import random
import sqlite3
import tempfile
import unittest
from pathlib import Path

from campaign_qc.config import CampaignConfig, load_config
from campaign_qc.generate import FIELDS, generate_customers
from campaign_qc.pipeline import (allocate, connect_database, export_results,
                                  import_customers, run_pipeline, stable_bucket, waterfall_rows)
from campaign_qc.qc import run_quality_checks

CFG = CampaignConfig.from_dict({
    "campaign_id": "DEMO26", "eligible_products": ["STREAM", "MOBILE"],
    "allowed_countries": ["US"], "max_contacts_30d": 3,
    "min_account_age_days": 30, "holdout_percent": 20,
})


def make_row(cid: str, **overrides: object) -> dict:
    row = {
        "customer_id": cid, "email": f"{cid.lower()}@example.com",
        "product_type": "STREAM", "country": "US", "is_active": 1,
        "marketing_opt_in": 1, "has_email": 1, "is_employee": 0,
        "is_legacy_subscriber": 0, "is_promotional_exclusion": 0,
        "contacts_30d": 1, "account_age_days": 100,
    }
    row.update(overrides)
    return row


def save_customers(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)


class CampaignTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_config_is_valid_and_rejects_bad_percentage(self):
        self.assertEqual(load_config(Path("config/demo_campaign.json")), CFG)
        bad = dict(json.loads(Path("config/demo_campaign.json").read_text()))
        bad["holdout_percent"] = 80
        with self.assertRaises(ValueError):
            CampaignConfig.from_dict(bad)

    def test_generator_reproducibility_and_reserved_addresses(self):
        p1, p2 = self.root / "a.csv", self.root / "b.csv"
        generate_customers(p1, 80, 42)
        generate_customers(p2, 80, 42)
        self.assertEqual(p1.read_bytes(), p2.read_bytes())
        self.assertIn(b"@example.com", p1.read_bytes())

    def test_end_to_end_outputs_and_pass(self):
        out = self.root / "out"
        result = run_pipeline(CFG, out, count=2000, seed=42)
        self.assertTrue(result["passed"])
        self.assertEqual(result["metrics"]["test"] + result["metrics"]["control"], result["metrics"]["eligible"])
        self.assertTrue((out / "campaign.sqlite3").is_file())
        self.assertTrue((out / "qc_report.md").is_file())
        self.assertEqual(len(result["checks"]), 8)
        control_header = (out / "exports" / "holdout_control.csv").read_text().splitlines()[0]
        self.assertNotIn("email", control_header)
        test_header = (out / "exports" / "sendable_test.csv").read_text().splitlines()[0]
        self.assertIn("email", test_header)
        self.assertEqual(result, json.loads((out / "qc_report.json").read_text()))

    def test_waterfall_order_and_eligibility_precedence(self):
        rows = [
            make_row("SYN1"),
            make_row("SYN2", is_active=0, is_employee=1),
            make_row("SYN3", product_type="LEGACY"),
            make_row("SYN4", country="CA"),
            make_row("SYN5", marketing_opt_in=0),
            make_row("SYN6", has_email=0, email=""),
            make_row("SYN7", is_employee=1),
            make_row("SYN8", is_legacy_subscriber=1),
            make_row("SYN9", is_promotional_exclusion=1),
            make_row("SYN10", contacts_30d=3),
            make_row("SYN11", account_age_days=29),
            make_row("SYN12", product_type="MOBILE"),
        ]
        p = self.root / "fixture.csv"
        save_customers(p, rows)
        con = connect_database(self.root / "fixture.sqlite3", CFG)
        self.addCleanup(con.close)
        import_customers(con, p)
        self.assertEqual([r["remaining"] for r in waterfall_rows(con)], list(range(12, 1, -1)))
        self.assertEqual(allocate(con, CFG), 2)
        self.assertTrue(run_quality_checks(con, CFG, waterfall_rows(con))["passed"])

    def test_idempotent_and_order_invariant_assignments(self):
        p1 = self.root / "original.csv"
        p2 = self.root / "reversed.csv"
        generate_customers(p1, 550, 9)
        with p1.open(newline="") as f:
            rows = list(csv.DictReader(f))
        save_customers(p2, list(reversed(rows)))
        a = run_pipeline(CFG, self.root / "run_a", input_csv=p1)
        b = run_pipeline(CFG, self.root / "run_b", input_csv=p2)
        self.assertEqual(a, b)
        for name in ("sendable_test.csv", "holdout_control.csv"):
            self.assertEqual((self.root / "run_a" / "exports" / name).read_bytes(),
                             (self.root / "run_b" / "exports" / name).read_bytes())
        c = run_pipeline(CFG, self.root / "run_a", input_csv=p1)
        self.assertEqual(a, c)

    def test_integrity_fails_when_allocation_missing(self):
        p = self.root / "synthetic.csv"
        generate_customers(p, 200, 12)
        con = connect_database(self.root / "tampered.sqlite3", CFG)
        self.addCleanup(con.close)
        import_customers(con, p)
        allocate(con, CFG)
        con.execute("DELETE FROM allocations WHERE customer_id = (SELECT customer_id FROM allocations LIMIT 1)")
        con.commit()
        checks = run_quality_checks(con, CFG, waterfall_rows(con))
        self.assertFalse(checks["passed"])
        self.assertFalse(next(c["passed"] for c in checks["checks"] if c["name"] == "Allocation coverage"))

    def test_invalid_and_duplicate_input_rejected(self):
        p = self.root / "duplicates.csv"
        save_customers(p, [make_row("SYN1"), make_row("SYN1")])
        con = connect_database(self.root / "invalid.sqlite3", CFG)
        self.addCleanup(con.close)
        with self.assertRaises(ValueError):
            import_customers(con, p)

    def test_bucket_boundaries(self):
        self.assertEqual(stable_bucket("DEMO26", "SYN1"), stable_bucket("DEMO26", "SYN1"))
        self.assertTrue(0 <= stable_bucket("DEMO26", "SYN2") < 10000)
        self.assertNotEqual(stable_bucket("DEMO26", "SYN1"), stable_bucket("OTHER", "SYN1"))


if __name__ == "__main__":
    unittest.main()
