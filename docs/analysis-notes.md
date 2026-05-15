# Analysis Notes & Methodology

**Analyst:** Teresiah Njoroge  
**Date:** January 2026  
**Database:** Agritech company operational database (PostgreSQL via DBeaver)  
**Analysis window:** Jul–Oct 2025 (90-day order health) + Apr–Oct 2025 (AR/pricing) + Oct 2024–Oct 2025 (DSO)

---

## Context

This analysis was built as a weekly operational health framework — a single structured SQL workbook covering the five domains leadership needs to monitor: order service quality, fulfilment, accounts receivable, pricing integrity, and sustainability impact.

The brief was to work with imperfect data: define each metric clearly, show a sanity check, and call out assumptions. If a data issue is found, document it and quantify how big it is.

---

## Data Issues Found and Resolved

### 1. COGS unit mismatch — caught and corrected
**Issue:** The initial below-cost sales query used `qty * (price - cogs)` to calculate margin. This produced results showing billions in losses — clearly wrong.

**Root cause:** In this schema, `order_line_items.cogs` is the **total cost for the entire line item** (pre-calculated as `buying_price × quantity`), not a per-unit cost. Treating it as per-unit and then multiplying by quantity again causes a 100x+ overstatement of cost.

**Fix:** `(qty * price) - cogs` — subtract total COGS from total revenue.

**Validated by:** Cross-checking a single line item manually: a line with qty=5, price=100, cogs=400 should produce a margin of 100 (5×100=500 revenue, 500-400=100 margin), not -1,500 (5×(100-400)).

---

### 2. `NOW()` replaced with hardcoded dates
**Issue:** Using `NOW() - INTERVAL '90 days'` makes queries non-reproducible — the same query run on different days returns different datasets, making it impossible to verify results or share findings.

**Fix:** Confirmed the min/max order dates in the dataset first, then hardcoded the date range in every query. The dates used are:
- Short window (90 days): `DATE '2025-07-23'` to `DATE '2025-10-21'`
- Medium window (180 days): `DATE '2025-04-24'` to `DATE '2025-10-21'`
- Long window (1 year): `DATE '2024-10-21'` to `DATE '2025-10-21'`

---

### 3. Cancellation signal — dual source required
**Issue:** Cancelled orders can be identified via `cancelled_at IS NOT NULL` OR `status ILIKE '%cancel%'`, but both are inconsistently populated. Using only one signal misses a subset of true cancellations.

**Approach:** Both signals combined in Query 1. The assumption and its limitation are documented in the query comments.

---

### 4. Routing coverage gap (~0.08% of orders)
**Issue:** Only ~0.08% of orders are linked to `route_orders`. The join on `order_number` between orders and route_orders returns almost no results.

**Impact:** Driver-level and route-level late delivery analysis is technically possible but statistically meaningless at this coverage level.

**Decision:** Late delivery analysis focuses on the statistically reliable dimensions (day of week, delivery slot). Route and driver columns are included in the query output but flagged as unreliable. The gap is documented rather than suppressed.

---

### 5. Impact metrics (kgs_rescued, co2_tonnes) not populated for top products
**Issue:** `kgs_rescued` and `co2_tonnes` are NULL for several top revenue products in `order_line_items`. COALESCE fills these with 0, but 0 is not the same as verified zero impact.

**Impact:** Product-level impact analysis (Query 9) cannot reliably rank products by impact until these fields are populated upstream.

**Decision:** Flagged in query comments and analysis notes. Monthly impact trend (Query 8) is still reliable at the aggregated level — the NULL issue primarily affects product-level granularity.

---

## Metric Definitions

| Metric | Definition |
|---|---|
| Cancel rate | Orders with `cancelled_at IS NOT NULL` OR `status ILIKE '%cancel%'` ÷ total orders |
| OTIF (on_time_rate) | Orders where `on_time_delivery = TRUE` ÷ orders where `on_time_delivery IS NOT NULL` |
| Fill rate | `SUM(quantity_received)` ÷ `SUM(order_quantity)` |
| Gross margin (line) | `(qty_received × selling_price) - cogs` |
| DSO | `invoice_paid_at::date - invoice_issue_date::date` (paid orders only) |
| Overdue | `invoice_paid_at IS NULL AND invoice_due_date < reference_date AND invoice_issue_date IS NOT NULL` |
| Late | `on_time_delivery = FALSE` |

---

## Assumptions

1. `deleted_at IS NULL` applied to both orders and order_line_items in all queries — soft-deleted records excluded throughout.
2. `NULLIF` used consistently for all division operations to prevent divide-by-zero errors.
3. `COALESCE` applied to quantity fields (order_quantity, quantity_received, kgs_rescued, co2_tonnes) — NULLs treated as zero in aggregations, with the exception noted for impact metrics.
4. `invoice_paid_at` is the source of truth for payment status — `payment_status` field not used as primary signal due to inconsistent population.
5. `product_unit_variant_id` in order_line_items joins to `products.id` for product name lookup — this join path requires schema validation as it bypasses the grade/variant hierarchy.

---

## Queries Index

| File | Steps Covered | Domain |
|---|---|---|
| `01_order_health_daily.sql` | Step 1 | Order health |
| `02_fill_rate_weekly.sql` | Step 2 | Fulfilment |
| `03_ar_and_dso.sql` | Steps 3, 4, 5 | AR / Collections |
| `04_pricing_audit.sql` | Steps 6, 7 | Pricing & margin |
| `05_impact_and_products.sql` | Steps 8, 9 | Impact & product performance |
| `06_late_delivery_patterns.sql` | Step 10 | Operations |
