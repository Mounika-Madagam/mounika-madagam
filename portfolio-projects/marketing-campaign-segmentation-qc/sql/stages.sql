-- One eligibility definition shared by audience creation and waterfall reporting.
-- Waterfall is ordered: the first disqualifying reason receives the exclusion count.
CREATE VIEW stage_00_source AS SELECT * FROM customers;
CREATE VIEW stage_01_active AS SELECT * FROM stage_00_source WHERE is_active = 1;
CREATE VIEW stage_02_product AS SELECT * FROM stage_01_active
  WHERE product_type IN (SELECT product_type FROM allowed_products);
CREATE VIEW stage_03_country AS SELECT * FROM stage_02_product
  WHERE country IN (SELECT country FROM allowed_countries);
CREATE VIEW stage_04_consent AS SELECT * FROM stage_03_country WHERE marketing_opt_in = 1;
CREATE VIEW stage_05_email AS SELECT * FROM stage_04_consent
  WHERE has_email = 1 AND TRIM(email) <> '';
CREATE VIEW stage_06_employee AS SELECT * FROM stage_05_email WHERE is_employee = 0;
CREATE VIEW stage_07_legacy AS SELECT * FROM stage_06_employee WHERE is_legacy_subscriber = 0;
CREATE VIEW stage_08_promo AS SELECT * FROM stage_07_legacy WHERE is_promotional_exclusion = 0;
CREATE VIEW stage_09_contact_cap AS SELECT * FROM stage_08_promo
  WHERE contacts_30d < CAST((SELECT value FROM campaign_settings WHERE name = 'max_contacts_30d') AS INTEGER);
CREATE VIEW stage_10_tenure AS SELECT * FROM stage_09_contact_cap
  WHERE account_age_days >= CAST((SELECT value FROM campaign_settings WHERE name = 'min_account_age_days') AS INTEGER);
CREATE VIEW eligible_audience AS SELECT * FROM stage_10_tenure;

CREATE VIEW waterfall AS
SELECT 0 AS step, 'Starting population' AS stage, COUNT(*) AS remaining FROM stage_00_source
UNION ALL SELECT 1, 'Active accounts', COUNT(*) FROM stage_01_active
UNION ALL SELECT 2, 'Eligible product', COUNT(*) FROM stage_02_product
UNION ALL SELECT 3, 'Allowed country', COUNT(*) FROM stage_03_country
UNION ALL SELECT 4, 'Marketing consent', COUNT(*) FROM stage_04_consent
UNION ALL SELECT 5, 'Valid email', COUNT(*) FROM stage_05_email
UNION ALL SELECT 6, 'Employee exclusion', COUNT(*) FROM stage_06_employee
UNION ALL SELECT 7, 'Legacy subscriber exclusion', COUNT(*) FROM stage_07_legacy
UNION ALL SELECT 8, 'Promotional exclusion', COUNT(*) FROM stage_08_promo
UNION ALL SELECT 9, 'Contact frequency cap', COUNT(*) FROM stage_09_contact_cap
UNION ALL SELECT 10, 'Minimum account age', COUNT(*) FROM stage_10_tenure;
