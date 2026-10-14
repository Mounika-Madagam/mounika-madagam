"""Deterministic synthetic customer generator. All addresses are fake example.com addresses."""

from __future__ import annotations

import csv
import random
from pathlib import Path

FIELDS = [
    "customer_id", "email", "product_type", "country", "is_active",
    "marketing_opt_in", "has_email", "is_employee", "is_legacy_subscriber",
    "is_promotional_exclusion", "contacts_30d", "account_age_days",
]


def generate_customers(path: Path, count: int = 3000, seed: int = 42) -> Path:
    if count <= 0 or count > 1_000_000:
        raise ValueError("count must be between 1 and 1,000,000")
    rng = random.Random(seed)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        for i in range(1, count + 1):
            has_email = int(rng.random() < 0.94)
            writer.writerow({
                "customer_id": f"SYN{i:07d}",
                "email": f"synthetic{i:07d}@example.com" if has_email else "",
                "product_type": rng.choices(["STREAM", "MOBILE", "LEGACY"], weights=[45, 40, 15])[0],
                "country": rng.choices(["US", "CA"], weights=[91, 9])[0],
                "is_active": int(rng.random() < 0.91),
                "marketing_opt_in": int(rng.random() < 0.88),
                "has_email": has_email,
                "is_employee": int(rng.random() < 0.04),
                "is_legacy_subscriber": int(rng.random() < 0.08),
                "is_promotional_exclusion": int(rng.random() < 0.05),
                "contacts_30d": rng.choices([0, 1, 2, 3, 4, 5], weights=[32, 28, 20, 12, 6, 2])[0],
                "account_age_days": rng.randint(0, 2000),
            })
    return path
