"""Configuration validation and loading."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class CampaignConfig:
    campaign_id: str
    eligible_products: tuple[str, ...]
    allowed_countries: tuple[str, ...]
    max_contacts_30d: int
    min_account_age_days: int
    holdout_percent: int

    @classmethod
    def from_dict(cls, data: dict) -> "CampaignConfig":
        expected = {
            "campaign_id", "eligible_products", "allowed_countries",
            "max_contacts_30d", "min_account_age_days", "holdout_percent",
        }
        if set(data) != expected:
            raise ValueError(f"Configuration keys must be exactly {sorted(expected)}")
        campaign_id = data["campaign_id"]
        if not isinstance(campaign_id, str) or not re.fullmatch(r"[A-Z][A-Z0-9_-]{2,29}", campaign_id):
            raise ValueError("campaign_id must be 3–30 uppercase letters/digits/_/- and start with a letter")
        for key in ("eligible_products", "allowed_countries"):
            values = data[key]
            if (not isinstance(values, list) or not values or
                    not all(isinstance(v, str) and re.fullmatch(r"[A-Z0-9_]{2,30}", v) for v in values) or
                    len(set(values)) != len(values)):
                raise ValueError(f"{key} must be a nonempty list of unique uppercase codes")
        for key in ("max_contacts_30d", "min_account_age_days", "holdout_percent"):
            value = data[key]
            if type(value) is not int:
                raise ValueError(f"{key} must be an integer")
        if not 1 <= data["max_contacts_30d"] <= 100:
            raise ValueError("max_contacts_30d must be between 1 and 100")
        if not 0 <= data["min_account_age_days"] <= 36500:
            raise ValueError("min_account_age_days must be between 0 and 36500")
        if not 1 <= data["holdout_percent"] <= 50:
            raise ValueError("holdout_percent must be between 1 and 50")
        return cls(campaign_id, tuple(data["eligible_products"]),
                   tuple(data["allowed_countries"]), data["max_contacts_30d"],
                   data["min_account_age_days"], data["holdout_percent"])


def load_config(path: Path) -> CampaignConfig:
    with path.open("r", encoding="utf-8") as f:
        return CampaignConfig.from_dict(json.load(f))
