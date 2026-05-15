-- ============================================================
-- QUERY 3: Invoice aging snapshot
-- ============================================================
-- Purpose: Categorise all invoices into four states —
-- PAID, OVERDUE, ISSUED_NOT_DUE, NOT_ISSUED — to assess
-- the health of accounts receivable.
--
-- Key design decisions:
-- • CASE priority order matters: PAID is checked before OVERDUE.
--   An invoice with both invoice_paid_at AND a past due date
--   should be classified as PAID, not OVERDUE.
-- • Static reference date '2025-10-21' used instead of NOW()
--   to simulate "today" for the historical dataset.
-- • 180-day window captures the active AR book without pulling
--   in very old orders that may have different data quality.
--
-- Assumptions:
-- • Invoices paid late are still classified as PAID — no
--   timing check at this stage.
-- • invoice_paid_at being populated is the source of truth
--   for payment — payment_status field not used as primary
--   signal due to inconsistent population.
-- ============================================================

WITH base AS (
    SELECT
        o.id,
        o.company_id,
        o.total_amount,
        o.invoice_issue_date,
        o.invoice_due_date,
        o.invoice_paid_at,
        o.payment_status,
        CASE
            WHEN o.invoice_issue_date IS NULL                       THEN 'NOT_ISSUED'
            WHEN o.invoice_paid_at IS NOT NULL                      THEN 'PAID'
            WHEN o.invoice_due_date IS NOT NULL
             AND o.invoice_due_date < DATE '2025-10-21'             THEN 'OVERDUE'
            ELSE 'ISSUED_NOT_DUE'
        END AS invoice_state
    FROM orders o
    WHERE o.deleted_at IS NULL
      AND o.order_date BETWEEN DATE '2025-04-24' AND DATE '2025-10-21'
)
SELECT
    invoice_state,
    COUNT(*)            AS orders,
    SUM(total_amount)   AS total_amount
FROM base
GROUP BY 1
ORDER BY 3 DESC;

-- Key findings:
-- • OVERDUE dominates the AR book — significant multi-million KES exposure
-- • Very few invoices marked PAID across the 6-month window — low
--   for a healthy B2B cycle
-- • Very few ISSUED_NOT_DUE → possible delays in invoice issuance
-- • Signals: credit policy gaps, collections process issues,
--   or inaccurate status tracking


-- ============================================================
-- QUERY 4: DSO (days sales outstanding) distribution
-- ============================================================
-- Purpose: Measure how long it takes customers to pay after
-- invoices are issued, using percentile distribution to
-- understand the full spread, not just the average.
--
-- Key design decisions:
-- • Only includes orders with BOTH invoice_issue_date AND
--   invoice_paid_at — unpaid invoices excluded (which makes
--   this a "paid invoice DSO", slightly optimistic vs true DSO
--   that would include outstanding invoices).
-- • Date cast to remove time component before subtraction —
--   otherwise timestamps produce fractional days.
-- • 1-year window to capture enough paid invoices for
--   meaningful percentile analysis.
-- • percentile_cont() gives true interpolated percentiles
--   (not discrete bucket edges).
-- ============================================================

WITH paid AS (
    SELECT
        o.id,
        o.company_id,
        o.total_amount,
        (o.invoice_paid_at::date - o.invoice_issue_date::date) AS days_to_pay
    FROM orders o
    WHERE o.deleted_at IS NULL
      AND o.invoice_issue_date IS NOT NULL
      AND o.invoice_paid_at IS NOT NULL
      AND o.order_date BETWEEN DATE '2024-10-21' AND DATE '2025-10-21'
)
SELECT
    COUNT(*)                                                        AS paid_orders,
    ROUND(AVG(days_to_pay)::numeric, 2)                            AS avg_days_to_pay,
    percentile_cont(0.5)  WITHIN GROUP (ORDER BY days_to_pay)      AS p50_days,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY days_to_pay)      AS p75_days,
    percentile_cont(0.90) WITHIN GROUP (ORDER BY days_to_pay)      AS p90_days
FROM paid;

-- Key findings:
-- • Avg days to pay: ~8 weeks — nearly 2 months to collect
-- • Median (p50): slightly above average — right-skewed distribution
-- • p75: >80 days — 25% of invoices take well over 2 months to collect
-- • Combined with aging analysis: confirms systemic slow-pay behaviour
-- • Action: review credit limits, reminder cadence, collections process


-- ============================================================
-- QUERY 5: Top companies by overdue exposure
-- ============================================================
-- Purpose: Rank customers by total overdue invoice value to
-- prioritise collections outreach and credit risk review.
--
-- Key design decisions:
-- • Overdue defined as: invoice issued + unpaid + due date
--   past the reference date. All three conditions required.
-- • qb_balance included from companies table — shows the
--   QuickBooks balance for cross-referencing, but may not
--   be real-time if sync is delayed.
-- • LIMIT 50 — top 50 customers by exposure. In practice,
--   the top 10 typically represent >80% of overdue value.
--
-- Assumptions:
-- • invoice_paid_at = NULL means unpaid. Partial payments
--   not tracked at order level — may slightly overstate exposure.
-- ============================================================

WITH overdue AS (
    SELECT
        o.company_id,
        COUNT(*)            AS overdue_orders,
        SUM(o.total_amount) AS overdue_amount
    FROM orders o
    WHERE o.deleted_at IS NULL
      AND o.invoice_issue_date IS NOT NULL
      AND o.invoice_paid_at IS NULL
      AND o.invoice_due_date IS NOT NULL
      AND o.invoice_due_date < DATE '2025-10-21'
    GROUP BY 1
)
SELECT
    c.id,
    '[ANONYMISED]'          AS company_name,
    c.invoice_due_days,
    c.qb_balance,
    overdue.overdue_orders,
    overdue.overdue_amount
FROM overdue
JOIN companies c ON c.id = overdue.company_id
ORDER BY overdue.overdue_amount DESC
LIMIT 50;

-- Top 10 findings (anonymised, amounts shown as approximate bands):
-- | Company     | Credit Terms | Overdue Orders | Overdue Exposure  |
-- |-------------|--------------|----------------|-------------------|
-- | Company A   | 30 days      | 150–250        | KES 8M–12M        |
-- | Company B   | 30 days      | 100–150        | KES 6M–10M        |
-- | Company C   | 30 days      | 100–150        | KES 3M–6M         |
-- | Company D   | 30 days      | 50–100         | KES 2M–4M         |
-- | Company E   | 30 days      | 100–150        | KES 2M–4M         |
-- | Company F   | 14 days      | 150–250        | KES 2M–4M         |
-- | Company G   | 14 days      | 100–150        | KES 2M–4M         |
-- | Company H   | 14 days      | 300–350        | KES 1M–2M         |
-- | Company I   | 14 days      | 200–250        | KES 1M–2M         |
-- | Company J   |  7 days      | 50–100         | KES 1M–2M         |
--
-- Key insight: Companies F–J have credit terms of 7–14 days but are
-- months overdue — signals poor enforcement, not just slow payment.
-- Company H: highest order count at 14-day terms is particularly notable.
