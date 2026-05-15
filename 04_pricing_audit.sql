-- ============================================================
-- QUERY 6: Below-cost line items (pricing & margin audit)
-- ============================================================
-- Purpose: Identify instances where products were sold below
-- COGS, resulting in negative gross margin per line item.
--
-- CRITICAL BUG CAUGHT AND FIXED:
-- Original query used: qty * (price - cogs) AS margin_per_line
-- This is WRONG. In this schema, cogs is the TOTAL cost for
-- the entire line item (not per unit). Treating it as per-unit
-- produced billions in fake losses.
--
-- Correct formula: (qty * price) - cogs AS margin_per_line
-- This subtracts the total COGS from total revenue per line.
--
-- How the bug was found: results showed impossibly large
-- negative margins. Schema investigation confirmed cogs is
-- populated as buying_price * quantity at order time.
--
-- Key design decisions:
-- • COALESCE on all quantity and price fields — NULLs in any
--   of these would zero out the line, masking real issues.
-- • quantity_received preferred over order_quantity — we want
--   margin on what was actually delivered, not what was ordered.
-- • WHERE price < cogs filters to below-cost lines only.
-- • GROUP BY company + product to surface systemic patterns
--   vs one-off pricing errors.
-- ============================================================

WITH li AS (
    SELECT
        o.company_id,
        oli.product_unit_variant_id,
        p.name                                              AS product_name,
        COALESCE(oli.quantity_received, oli.order_quantity, 0) AS qty,
        COALESCE(oli.selling_price, 0)                      AS price,
        COALESCE(oli.cogs, 0)                               AS cogs
    FROM order_line_items oli
    JOIN orders o   ON o.id  = oli.order_id
    JOIN products p ON p.id  = oli.product_unit_variant_id
    WHERE oli.deleted_at IS NULL
      AND o.deleted_at IS NULL
      AND o.order_date >= DATE '2025-04-24'
)
SELECT
    company_id,
    product_unit_variant_id,
    product_name,
    SUM(qty)                            AS qty,
    -- Correct formula: total revenue minus total COGS
    SUM((qty * price) - cogs)           AS gross_margin_value
FROM li
WHERE price < cogs
GROUP BY 1, 2, 3
ORDER BY gross_margin_value ASC
LIMIT 100;

-- Key findings:
-- • Same products appear below cost across multiple companies
--   → systemic pricing/COGS issue, not isolated data errors
-- • Negative margins occur even at low/zero quantities
--   → possible misaligned COGS allocation or adjustment artifacts
-- • Top loss-making SKUs: [Product A] and [Product B] — audit pricing and cost inputs first
--
-- Recommendations:
-- 1. Audit top loss-making SKUs first — validate pricing and cost inputs
-- 2. Enforce pricing guardrail: selling_price < buying_price requires
--    explicit override approval before order can be confirmed
-- 3. Investigate zero-quantity loss lines — clean up COGS logic
--    or adjustment handling where needed


-- ============================================================
-- QUERY 7: Coupon vs non-coupon performance
-- ============================================================
-- Purpose: Assess whether coupon usage drives incremental
-- order volume and value, or simply applies discounts to
-- existing demand.
--
-- Key design decisions:
-- • Coupon bucket defined by EITHER coupon_id IS NOT NULL
--   OR coupon_discount_amount > 0 — both signals used because
--   either can be populated without the other.
-- • COALESCE(coupon_discount_amount, 0) before the >0 check
--   to avoid NULL comparison issues.
-- • cancel_rate uses cancelled_at IS NOT NULL as signal —
--   consistent with Query 1 approach.
-- • No OTIF split here — coupon vs service quality is a
--   separate investigation if this shows a gap.
-- ============================================================

WITH o AS (
    SELECT
        order_date::date    AS day,
        CASE
            WHEN coupon_id IS NOT NULL
              OR COALESCE(coupon_discount_amount, 0) > 0
            THEN 'COUPON'
            ELSE 'NO_COUPON'
        END                 AS bucket,
        total_amount,
        cancelled_at
    FROM orders
    WHERE deleted_at IS NULL
      AND order_date BETWEEN DATE '2025-04-24' AND DATE '2025-10-21'
)
SELECT
    bucket,
    COUNT(*)                            AS orders,
    ROUND(AVG(total_amount), 2)         AS avg_order_value,
    ROUND(
        SUM(CASE WHEN cancelled_at IS NOT NULL THEN 1 ELSE 0 END)::numeric
        / NULLIF(COUNT(*), 0),
        4
    )                                   AS cancel_rate
FROM o
GROUP BY 1;

-- Key findings:
-- • Coupon orders: <0.5% of total order volume
-- • Coupon avg order value: ~60% higher than non-coupon orders
-- • No cancellations observed in either group in this period
-- • Coupon orders appear to be high-intent, high-value purchases
--   not discount-driven low-value orders
-- • Implication: coupons may be functioning as a premium/unlock
--   mechanism rather than a volume acquisition tool
