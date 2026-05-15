# Data Dictionary

**Database:** Agritech company operational database (PostgreSQL)  
**Note:** No raw data is included in this repository. This dictionary describes the schema tables used in the analysis.

---

## Core Tables

### `orders`
Primary order header. One row per order.

| Column | Type | Used in |
|---|---|---|
| id | uuid | All queries (join key) |
| company_id | uuid | FK to companies |
| order_date | timestamp | All queries (date filtering) |
| total_amount | numeric | Q1, Q3, Q5, Q7 |
| status | varchar | Q1 (cancellation signal) |
| cancelled_at | timestamp | Q1, Q7 (cancellation signal) |
| on_time_delivery | boolean | Q1, Q10 (OTIF / late flag) |
| delivery_slot | varchar | Q10 |
| invoice_issue_date | date | Q3, Q4, Q5 |
| invoice_due_date | date | Q3, Q5 |
| invoice_paid_at | timestamp | Q3, Q4, Q5 |
| payment_status | varchar | Q3 (reference only) |
| coupon_id | uuid | Q7 |
| coupon_discount_amount | numeric | Q7 |
| order_number | varchar | Q10 (join to route_orders) |
| deleted_at | timestamp | All queries (soft delete filter) |

### `order_line_items`
One row per product per order.

| Column | Type | Notes |
|---|---|---|
| id | uuid | Primary key |
| order_id | uuid | FK to orders |
| product_unit_variant_id | uuid | FK to products (via variant hierarchy) |
| order_quantity | numeric | Quantity ordered by customer |
| quantity_received | numeric | Quantity actually delivered |
| selling_price | numeric | Per-unit price at time of order |
| cogs | numeric | **Total** line item cost (not per-unit). `cogs = buying_price × quantity`. See analysis notes for the unit mismatch bug caught during this analysis. |
| kgs_rescued | numeric | Kilograms of food rescued (NULL for many top products) |
| co2_tonnes | numeric | Tonnes of CO₂ avoided (NULL for many top products) |
| deleted_at | timestamp | Soft delete |

### `companies`
Customer accounts.

| Column | Type | Used in |
|---|---|---|
| id | uuid | Join key |
| name | varchar | Q5 (anonymised in outputs) |
| invoice_due_days | int | Q5 (credit terms) |
| qb_balance | numeric | Q5 (QuickBooks balance) |

### `products`
Master product catalogue.

| Column | Type | Used in |
|---|---|---|
| id | uuid | Join key (from product_unit_variant_id) |
| name | varchar | Q6, Q9 |

### `routes`
Route plan records.

| Column | Type | Used in |
|---|---|---|
| id | uuid | Q10 |
| driver_id | int | Q10 |

### `route_orders`
Links orders to routes.

| Column | Type | Notes |
|---|---|---|
| route_id | uuid | FK to routes |
| order_number | varchar | Join key to orders.order_number |

**Coverage note:** Only ~0.08% of orders are linked to route_orders. Driver- and route-level analysis in Q10 is not statistically reliable at this coverage level.

---

## Anonymisation Note

All customer company names appearing in query results have been replaced with generic identifiers (Company A–J) in this repository. No raw database exports are included.

The company operating the database has been described generically as "a Kenyan agritech company" throughout.
