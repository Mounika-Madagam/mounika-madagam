# Campaign quality-control report

Campaign: **DEMO26**

- Starting customers: **3000**
- Eligible customers: **1148**
- Test: **912**
- Control (non-sendable): **236**
- Overall status: **PASS**

## Sequential waterfall

| Step | Rule | Remaining | Excluded at step |
| ---: | --- | ---: | ---: |
| 0 | Starting population | 3000 | 0 |
| 1 | Active accounts | 2719 | 281 |
| 2 | Eligible product | 2314 | 405 |
| 3 | Allowed country | 2110 | 204 |
| 4 | Marketing consent | 1877 | 233 |
| 5 | Valid email | 1768 | 109 |
| 6 | Employee exclusion | 1692 | 76 |
| 7 | Legacy subscriber exclusion | 1554 | 138 |
| 8 | Promotional exclusion | 1468 | 86 |
| 9 | Contact frequency cap | 1164 | 304 |
| 10 | Minimum account age | 1148 | 16 |

## Automated quality gates

| Check | Result | Details |
| --- | --- | --- |
| Waterfall is monotonic | PASS | No step can gain customers |
| Waterfall exclusion reconciliation | PASS | Step exclusions equal starting population minus eligible population |
| Allocation coverage | PASS | Exactly one row per eligible customer and no ineligible allocations |
| Independent eligibility audit | PASS | SQL eligibility agrees with independent Python rule evaluation |
| Distinct test/control cohorts | PASS | No customer appears in both cohorts |
| Deterministic assignment | PASS | Recomputed hash buckets reproduce all control assignments |
| Cell code and product integrity | PASS | Cell metadata matches campaign, product, segment, and source |
| Holdout allocation within 5 percentage points | PASS | Configured 20% vs actual 20.56% (small n < 100 exempt) |

**Note:** Test and control counts follow a stable hash allocation; the split is approximately, not exactly, the configured percentage. All customers are synthetic.
