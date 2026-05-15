-- ============================================================
-- QUERY 10: Late delivery patterns by slot, day, route, driver
-- ============================================================
-- Purpose: Identify structural drivers of late deliveries —
-- whether lateness clusters by time of day, day of week,
-- delivery slot, specific routes, or individual drivers.
--
-- Key design decisions:
-- • on_time_delivery flag used as the lateness signal —
--   the schema does not reliably populate delivered_at
--   timestamps, ruling out duration-based diagnostics.
-- • is_late = CASE WHEN on_time_delivery = FALSE THEN 1 ELSE 0
--   — only false is late; true is on-time; NULL is excluded
--   from the rate calculation via AVG (AVG ignores NULLs).
--   Using COUNT FILTER on is_late = 1 / COUNT(*) would
--   incorrectly count NULLs as on-time.
-- • LEFT JOIN to route_orders and routes — most orders are
--   NOT in route_orders (~0.08% coverage). LEFT JOIN preserves
--   all orders; route/driver fields will be NULL for most rows.
-- • HAVING COUNT(*) >= 30 — minimum threshold for statistical
--   reliability. Groups with <30 orders produce unstable rates.
-- • cancelled_at IS NULL — excludes cancelled orders from
--   delivery performance analysis.
--
-- Critical data gap:
-- Route coverage is ~0.08% of orders. Route- and driver-level
-- findings are NOT statistically reliable. This analysis
-- documents the gap rather than forcing an unreliable conclusion.
-- ============================================================

WITH base AS (
    SELECT
        EXTRACT(DOW FROM o.order_date)  AS dow,
        o.delivery_slot,
        ro.route_id,
        r.driver_id,
        CASE
            WHEN o.on_time_delivery = FALSE THEN 1
            ELSE 0
        END                             AS is_late
    FROM orders o
    LEFT JOIN route_orders ro ON ro.order_number = o.order_number
    LEFT JOIN routes r        ON r.id = ro.route_id
    WHERE o.deleted_at IS NULL
      AND o.cancelled_at IS NULL
      AND o.on_time_delivery IS NOT NULL
)
SELECT
    dow,
    delivery_slot,
    route_id,
    driver_id,
    COUNT(*)                                    AS total_orders,
    COUNT(*) FILTER (WHERE is_late = 1)         AS late_orders,
    ROUND(AVG(is_late::numeric), 4)             AS late_rate
FROM base
GROUP BY 1, 2, 3, 4
HAVING COUNT(*) >= 30
ORDER BY late_rate DESC;

-- Key findings:
-- • Late deliveries are NOT randomly distributed
-- • 13:00–16:00 delivery slot consistently shows highest late rates
-- • Late rates peak on weekdays (Tue–Fri); Friday PM performs worst
-- • Morning and midday slots perform better, still above benchmark
-- • Route/driver dimensions: largely NULL — not statistically usable
--
-- DOW reference: 0 = Sunday, 1 = Monday, ..., 5 = Friday, 6 = Saturday
--
-- Recommendations:
-- 1. Reduce order acceptance for 13:00–16:00 Friday PM slot,
--    or shift dispatch 1–2 hours earlier
-- 2. Investigate whether Friday PM late rate is driven by
--    route density (too many stops) or traffic patterns
-- 3. Fix route_orders linkage to unlock driver-level analysis —
--    currently this dimension is analytically blind
