PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS customers (
    customer_id TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    product_type TEXT NOT NULL,
    country TEXT NOT NULL,
    is_active INTEGER NOT NULL CHECK (is_active IN (0, 1)),
    marketing_opt_in INTEGER NOT NULL CHECK (marketing_opt_in IN (0, 1)),
    has_email INTEGER NOT NULL CHECK (has_email IN (0, 1)),
    is_employee INTEGER NOT NULL CHECK (is_employee IN (0, 1)),
    is_legacy_subscriber INTEGER NOT NULL CHECK (is_legacy_subscriber IN (0, 1)),
    is_promotional_exclusion INTEGER NOT NULL CHECK (is_promotional_exclusion IN (0, 1)),
    contacts_30d INTEGER NOT NULL CHECK (contacts_30d >= 0),
    account_age_days INTEGER NOT NULL CHECK (account_age_days >= 0)
);

CREATE TABLE IF NOT EXISTS campaign_settings (
    name TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS allowed_products (product_type TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS allowed_countries (country TEXT PRIMARY KEY);

CREATE TABLE IF NOT EXISTS allocations (
    customer_id TEXT PRIMARY KEY REFERENCES customers(customer_id),
    product_type TEXT NOT NULL,
    segment TEXT NOT NULL CHECK (segment IN ('TEST', 'CONTROL')),
    bucket INTEGER NOT NULL CHECK (bucket BETWEEN 0 AND 9999),
    cell_name TEXT NOT NULL,
    cell_code TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_allocations_segment ON allocations(segment);
