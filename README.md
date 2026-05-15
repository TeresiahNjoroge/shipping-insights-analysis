# Shipping Insights: Operational Analytics

**Tools:** PostgreSQL · DBeaver · SQL  
**Skills demonstrated:** Multi-domain operational analytics · AR/finance analysis · Data quality debugging · Pricing audit · Impact reporting  
**Status:** Complete — January 2026

---

## The Business Question

A Kenyan agritech company running B2B fresh produce distribution needed a weekly operational health check across four domains: **order fulfilment, accounts receivable, pricing integrity, and sustainability impact**.

Rather than separate one-off reports, the goal was a single analytical framework answering:

1. How healthy is our order volume and service quality?
2. Are we fulfilling what customers order?
3. How bad is our overdue AR exposure — and who owes what?
4. Where are we selling below cost, and does coupon usage actually help?
5. Are we growing our environmental impact, and which products drive it?
6. What is causing late deliveries?

---

## Key Findings

| Domain | Finding |
|---|---|
| Order health | 52 days of clean daily data; cancel rate and OTIF consistent with operational patterns |
| Fill rate | Weekly fill rate tracked across 13 weeks; short-delivery patterns identified |
| AR / invoicing | **Multi-million KES overdue exposure**; very few invoices paid in 6 months — serious collections risk |
| DSO | Collection takes ~8 weeks on average; **top quartile beyond 80 days** — slow-pay is systemic, not isolated |
| Pricing | Below-cost sales confirmed across multiple companies and SKUs — systemic, not data error |
| Coupons | <0.5% of orders use coupons, but coupon AOV is **~60% higher** than non-coupon |
| Impact | Monthly kgs rescued and CO₂ trend tracked; impact data missing for top revenue SKUs |
| Late delivery | **13:00–16:00 slot** and **Friday PM** have highest late rates; route data too sparse for driver-level diagnosis |

---

## What Made This Analysis Hard

**1. COGS unit mismatch — caught and fixed**  
The initial below-cost query used `qty * (price - cogs)` — but `cogs` in this schema is the total line item cost, not per-unit. This produced billions in fake losses. Fixed to `(qty * price) - cogs` after schema investigation.

**2. Cancellation signal is ambiguous**  
Cancelled orders can be identified via `cancelled_at IS NOT NULL` OR `status ILIKE '%cancel%'` — but both fields are inconsistently populated. Both signals used in combination with documentation of the assumption.

**3. Routing coverage is near-zero**  
Only ~0.08% of orders are linked to `route_orders`. Driver- and route-level late delivery analysis was technically possible but statistically meaningless. Documented as a data gap rather than forcing an unreliable output.

**4. `NOW()` replaced with fixed dates**  
The original queries used `NOW() - INTERVAL '90 days'` which makes results non-reproducible. All queries use hardcoded date ranges based on the confirmed data window (max and min order dates verified first).

**5. Impact metrics unpopulated for top products**  
`kgs_rescued` and `co2_tonnes` are NULL for several top revenue products. The analysis notes this explicitly rather than treating zeros as true values.

---

## Analysis Scope: 10 Steps

| Step | Question | Domain |
|---|---|---|
| 1 | Daily order volume, AOV, cancel rate, OTIF | Order health |
| 2 | Weekly fill rate (ordered vs received) | Fulfilment |
| 3 | Invoice aging: paid / overdue / not issued | AR |
| 4 | DSO distribution: median, p75, p90 | AR |
| 5 | Top companies by overdue exposure | AR / Collections |
| 6 | Below-cost line items by product and customer | Pricing |
| 7 | Coupon vs non-coupon: AOV and cancel rate | Pricing |
| 8 | Monthly kgs rescued and CO₂ trend | Impact |
| 9 | Product leaderboard: revenue, margin, fill rate, impact | Product |
| 10 | Late delivery patterns by slot, day, route | Operations |

---

## Repository Structure

```
shipping-insights-analysis/
│
├── README.md                       ← You are here
│
├── queries/
│   ├── 01_order_health_daily.sql   ← Daily order trend, cancel rate, OTIF
│   ├── 02_fill_rate_weekly.sql     ← Ordered vs received quantities by week
│   ├── 03_invoice_aging.sql        ← AR state: paid / overdue / not issued
│   ├── 04_dso_distribution.sql     ← Days to pay: avg, p50, p75, p90
│   ├── 05_overdue_companies.sql    ← Top companies by overdue exposure
│   ├── 06_below_cost_sales.sql     ← Products selling below COGS
│   ├── 07_coupon_performance.sql   ← Coupon vs non-coupon order behaviour
│   ├── 08_impact_monthly.sql       ← Monthly kgs rescued + CO₂ trend
│   ├── 09_product_performance.sql  ← Revenue, margin, fill rate, impact per SKU
│   └── 10_late_delivery_patterns.sql ← Late rate by slot, day, route, driver
│
├── docs/
│   └── analysis-notes.md           ← Methodology, assumptions, data gaps
│
└── data/
    └── data-dictionary.md          ← Schema reference (no raw data included)
```

---

## Three Recommendations from the Analysis

**1. Credit policy — immediate action**  
Overdue AR exposure spans multiple millions of KES with a median collection time exceeding 60 days. Companies on 7–14 day terms are months overdue. Recommend: automated reminder escalation at 7, 14, and 21 days post-due; credit hold at 30+ days outstanding.

**2. Pricing guardrails — system fix**  
Below-cost sales are confirmed across multiple products and customers. This is not a data artifact — the COGS unit mismatch was corrected before this finding. Recommend: pricing rule enforcement preventing `selling_price < buying_price` without explicit override approval.

**3. Operations — slot and day optimisation**  
The 13:00–16:00 slot and Friday PM consistently show the highest late rates. Recommend: reduce order acceptance for Friday PM slots, or add buffer time by shifting dispatch earlier.

---

## Data & Privacy Note

No raw company data is included in this repository. Customer names from the overdue analysis have been anonymised (Company A–J). All outputs show aggregated metrics, rates, and counts only.

---

## Analyst

Teresiah Njoroge · [linkedin.com/in/teresiah-njoroge](https://www.linkedin.com/in/teresiah-njoroge) · [github.com/TeresiahNjoroge](https://github.com/TeresiahNjoroge)
