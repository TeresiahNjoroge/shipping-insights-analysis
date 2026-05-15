-- ============================================================
-- QUERY 1: Daily order health
-- ============================================================
-- Purpose: Track daily order volume, revenue, average basket
-- size, cancellation rate, and OTIF over a fixed 90-day window.
--
-- Key design decisions:
-- • NOW() replaced with hardcoded dates — using NOW() makes
--   results non-reproducible across runs. Dates set to the
--   confirmed min/max range in the dataset.
-- • Cancellation detected via BOTH cancelled_at timestamp AND
--   status ILIKE '%cancel%'. Both signals inconsistently
--   populated — combining them catches more true cancellations.
-- • OTIF uses AVG(CASE WHEN on_time_delivery IS TRUE THEN 1
--   WHEN FALSE THEN 0 ELSE NULL END) — the ELSE NULL ensures
--   NULLs are excluded from the denominator, not counted as
--   late. Critical: many orders have NULL on_time_delivery.
-- ============================================================

WITH o AS (
    SELECT
        id,
        company_id,
        order_date::date                AS order_day,
        status,
        on_time_delivery,
        total_amount,
        cancelled_at
    FROM orders
    WHERE deleted_at IS NULL
      AND order_date >= DATE '2025-07-23'
      AND order_date <= DATE '2025-10-21'
)
SELECT
    order_day,
    COUNT(*)                            AS orders,
    SUM(total_amount)                   AS total_amount,
    ROUND(AVG(total_amount), 2)         AS avg_order_value,
    ROUND(
        SUM(
            CASE
                WHEN cancelled_at IS NOT NULL
                  OR status ILIKE '%cancel%'
                THEN 1 ELSE 0
            END
        )::numeric / NULLIF(COUNT(*), 0),
        4
    )                                   AS cancel_rate,
    ROUND(
        AVG(
            CASE
                WHEN on_time_delivery IS TRUE  THEN 1
                WHEN on_time_delivery IS FALSE THEN 0
                ELSE NULL
            END
        )::numeric,
        4
    )                                   AS on_time_rate
FROM o
GROUP BY 1
ORDER BY 1 DESC;

-- Result: 52 rows returned. Trends clean and interpretable.
-- Data issues to monitor:
--   • Are cancelled_at timestamps always filled for cancelled orders?
--   • Status values: 'cancel', 'cancelled', 'Cancelled' — check variants
--   • What share of rows have NULL on_time_delivery?
--   • Any outlier order amounts (>5x average)?
