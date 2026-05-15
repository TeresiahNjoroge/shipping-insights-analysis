-- ============================================================
-- QUERY 8: Monthly impact trend (kgs rescued + CO₂)
-- ============================================================
-- Purpose: Track how environmental impact evolves month by
-- month — whether rescued food and CO₂ avoidance are growing,
-- stable, or declining.
--
-- Key design decisions:
-- • Line-item level aggregation (not order level) — impact
--   metrics are on order_line_items, not orders. Using the
--   order level would require a join and potentially miss
--   partial fulfilment impact.
-- • COALESCE to 0 prevents NULLs from silently dropping
--   line items from SUM — but note: zero ≠ truly zero impact.
--   Top revenue products have NULL impact fields (see Query 9).
-- • date_trunc('month') cast to ::date for clean output.
-- • Uses NOW() - INTERVAL '365 days' — this query retained
--   rolling window for ongoing monitoring use; adjust to
--   hardcoded dates for point-in-time reproducibility.
--
-- Assumptions:
-- • kgs_rescued and co2_tonnes are additive across line items
--   (no double-counting at order level).
-- • Impact metrics are correctly calculated upstream — not
--   validated in this analysis.
-- • Does not normalise impact by revenue or order volume.
-- ============================================================

SELECT
    date_trunc('month', o.order_date)::date     AS month,
    SUM(COALESCE(oli.kgs_rescued, 0))           AS kgs_rescued,
    SUM(COALESCE(oli.co2_tonnes, 0))            AS co2_tonnes
FROM order_line_items oli
JOIN orders o ON o.id = oli.order_id
WHERE oli.deleted_at IS NULL
  AND o.deleted_at IS NULL
  AND o.order_date >= DATE '2024-10-21'
GROUP BY 1
ORDER BY 1 DESC;

-- Sanity check before reading results:
-- If kgs_rescued is 0 for most months, check whether the field
-- is populated upstream. Zero-filled COALESCE can mask a data gap.


-- ============================================================
-- QUERY 9: Product performance leaderboard
-- ============================================================
-- Purpose: Rank products by commercial performance (revenue,
-- margin) alongside operational reliability (fill rate) and
-- environmental impact — surfacing trade-offs and priorities.
--
-- Key design decisions:
-- • Revenue = qty_received × price (not qty_ordered × price)
--   — only charge for what was delivered. Avoids overstating
--   revenue from unfulfilled orders.
-- • Margin = (qty_received × price) - cogs — uses the corrected
--   formula from Query 6. COGS is the total line item cost.
-- • Fill rate = qty_received / qty_ordered — values >1.0 flag
--   over-delivery or order quantity adjustments (not an error,
--   but worth flagging to operations).
-- • product_unit_variant_id used in base CTE, then joined to
--   products — NOTE: this join assumes product_unit_variant_id
--   maps directly to products.id, which requires schema
--   validation. If wrong, product names will be NULL.
-- ============================================================

WITH base AS (
    SELECT
        oli.product_unit_variant_id                         AS product_id,
        COALESCE(oli.quantity_received, 0)                  AS qty_received,
        COALESCE(oli.order_quantity, 0)                     AS qty_ordered,
        COALESCE(oli.selling_price, 0)                      AS price,
        COALESCE(oli.cogs, 0)                               AS cogs,
        COALESCE(oli.kgs_rescued, 0)                        AS kgs_rescued,
        COALESCE(oli.co2_tonnes, 0)                         AS co2_tonnes
    FROM order_line_items oli
    JOIN orders o ON o.id = oli.order_id
    WHERE oli.deleted_at IS NULL
      AND o.deleted_at IS NULL
      AND o.order_date BETWEEN DATE '2025-04-24' AND DATE '2025-10-21'
),
product_perf AS (
    SELECT
        product_id,
        SUM(qty_received * price)                           AS revenue,
        -- Corrected margin formula (see Query 6 note)
        SUM(qty_received * price - cogs)                    AS gross_margin,
        ROUND(
            SUM(qty_received) / NULLIF(SUM(qty_ordered), 0),
            4
        )                                                   AS fill_rate,
        SUM(kgs_rescued)                                    AS total_kgs_rescued,
        SUM(co2_tonnes)                                     AS total_co2_tonnes
    FROM base
    GROUP BY 1
)
SELECT
    p.id                    AS product_id,
    p.name                  AS product_name,
    pp.revenue,
    pp.gross_margin,
    pp.fill_rate,
    pp.total_kgs_rescued,
    pp.total_co2_tonnes
FROM product_perf pp
JOIN products p ON p.id = pp.product_id
ORDER BY pp.revenue DESC
LIMIT 50;

-- Key findings:
-- • Revenue is concentrated in a small number of staple products
-- • Gross margins are positive but thin — consistent with
--   commodity-style fresh produce pricing
-- • Fill rates are generally high (strong fulfilment performance)
-- • IMPORTANT: kgs_rescued and co2_tonnes are NULL for several
--   top-selling products — this is a data gap, not zero impact.
--   Impact analysis at product level is unreliable until populated.
-- • fill_rate >1.0 for some products: over-delivery or order
--   quantity adjustments — flag to operations for review
