-- ============================================================
-- QUERY 2: Weekly fill rate (ordered vs received)
-- ============================================================
-- Purpose: Evaluate how effectively the company fulfills what
-- customers order — comparing ordered vs received quantities
-- at line item level, grouped by week.
--
-- Key design decisions:
-- • COALESCE on quantity fields — order_quantity and
--   quantity_received can both be NULL. COALESCE to 0 avoids
--   NULL propagation into SUM and fill_rate calculation.
-- • date_trunc('week') for weekly grouping — gives ISO Monday-
--   anchored weeks, consistent across the 13-week window.
-- • NULLIF(SUM(ordered_qty), 0) — prevents divide-by-zero
--   when an entire week has no ordered quantities.
-- • Hardcoded dates instead of NOW() - INTERVAL for
--   reproducibility (see Query 1 note).
--
-- Assumptions:
-- • order_quantity and quantity_received are in the same unit.
-- • Returned/cancelled lines not separately flagged in
--   order_line_items — included unless marked deleted.
-- ============================================================

WITH li AS (
    SELECT
        oli.order_id,
        date_trunc('week', o.order_date)::date  AS week_start,
        COALESCE(oli.order_quantity, 0)          AS ordered_qty,
        COALESCE(oli.quantity_received, 0)       AS received_qty
    FROM order_line_items oli
    JOIN orders o ON o.id = oli.order_id
    WHERE oli.deleted_at IS NULL
      AND o.deleted_at IS NULL
      AND o.order_date BETWEEN DATE '2025-07-23' AND DATE '2025-10-21'
)
SELECT
    week_start,
    SUM(ordered_qty)                        AS ordered_qty,
    SUM(received_qty)                       AS received_qty,
    ROUND(
        SUM(received_qty) / NULLIF(SUM(ordered_qty), 0),
        4
    )                                       AS fill_rate
FROM li
GROUP BY 1
ORDER BY 1 DESC;

-- Result: 13 weekly rows covering the full 90-day window.
-- Fill rate shows whether we consistently fulfill customer expectations.
-- Values >1.0 indicate over-delivery or order quantity adjustments.
