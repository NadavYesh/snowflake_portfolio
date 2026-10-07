-- =====================================================================
-- Day 2 — SOLUTIONS. Try each exercise yourself first!
-- Data: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1
-- Revenue convention used here: l_extendedprice * (1 - l_discount)
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE DEV_WH;
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1;

-- ---------------------------------------------------------------------
-- A. Filtering & aggregation
-- ---------------------------------------------------------------------

-- 1. Customers per market segment
SELECT c_mktsegment, COUNT(*) AS customers
FROM customer
GROUP BY c_mktsegment
ORDER BY customers DESC;

-- 2. Nations whose average customer balance is above 4,500
SELECT n.n_name, ROUND(AVG(c.c_acctbal), 2) AS avg_balance
FROM customer c
JOIN nation n ON c.c_nationkey = n.n_nationkey
GROUP BY n.n_name
HAVING AVG(c.c_acctbal) > 4500          -- HAVING filters groups; WHERE filters rows
ORDER BY avg_balance DESC;

-- 3. Orders and order value per year
SELECT YEAR(o_orderdate) AS order_year,
       COUNT(*)          AS orders,
       ROUND(SUM(o_totalprice), 0) AS total_value
FROM orders
GROUP BY order_year
ORDER BY order_year;

-- 4. Per ship mode, for items shipped in 1997
SELECT l_shipmode,
       SUM(l_quantity)            AS total_qty,
       ROUND(AVG(l_discount), 4)  AS avg_discount
FROM lineitem
WHERE l_shipdate >= '1997-01-01' AND l_shipdate < '1998-01-01'   -- range filter, prunes well
GROUP BY l_shipmode
ORDER BY total_qty DESC;

-- ---------------------------------------------------------------------
-- B. Joins
-- ---------------------------------------------------------------------

-- 5. Net revenue per region
SELECT r.r_name AS region,
       ROUND(SUM(l.l_extendedprice * (1 - l.l_discount)), 0) AS revenue
FROM lineitem l
JOIN orders   o ON l.l_orderkey  = o.o_orderkey
JOIN customer c ON o.o_custkey   = c.c_custkey
JOIN nation   n ON c.c_nationkey = n.n_nationkey
JOIN region   r ON n.n_regionkey = r.r_regionkey
GROUP BY region
ORDER BY revenue DESC;

-- 6. Customers who never placed an order (anti-join)
SELECT COUNT(*) AS customers_without_orders
FROM customer c
LEFT JOIN orders o ON o.o_custkey = c.c_custkey
WHERE o.o_orderkey IS NULL;
-- Alternative: WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.o_custkey = c.c_custkey)

-- 7. Top 5 suppliers by 1996 revenue, with their nation
SELECT s.s_name, n.n_name AS nation,
       ROUND(SUM(l.l_extendedprice * (1 - l.l_discount)), 0) AS revenue_1996
FROM lineitem l
JOIN supplier s ON l.l_suppkey   = s.s_suppkey
JOIN nation   n ON s.s_nationkey = n.n_nationkey
WHERE l.l_shipdate >= '1996-01-01' AND l.l_shipdate < '1997-01-01'
GROUP BY s.s_name, n.n_name
ORDER BY revenue_1996 DESC
LIMIT 5;

-- 8. Share of line items received late (after commit date) per ship mode
SELECT l_shipmode,
       COUNT(*) AS items,
       COUNT_IF(l_receiptdate > l_commitdate) AS late_items,          -- Snowflake shortcut
       ROUND(100 * COUNT_IF(l_receiptdate > l_commitdate) / COUNT(*), 1) AS pct_late
       -- portable version: SUM(CASE WHEN l_receiptdate > l_commitdate THEN 1 ELSE 0 END)
FROM lineitem
GROUP BY l_shipmode
ORDER BY pct_late DESC;

-- 9. Orders with 7 line items, with customer name (the max in TPC-H)
SELECT o.o_orderkey, c.c_name, COUNT(*) AS line_items
FROM orders o
JOIN customer c ON o.o_custkey  = c.c_custkey
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
GROUP BY o.o_orderkey, c.c_name
HAVING COUNT(*) = 7
ORDER BY o.o_orderkey
LIMIT 20;

-- ---------------------------------------------------------------------
-- C. CTEs (WITH ... AS)
-- ---------------------------------------------------------------------

-- 10. Customer tiers by lifetime spend
WITH spend AS (
    SELECT o_custkey, SUM(o_totalprice) AS lifetime_spend
    FROM orders
    GROUP BY o_custkey
)
SELECT CASE
         WHEN lifetime_spend >= 3000000 THEN 'Gold'
         WHEN lifetime_spend >= 1000000 THEN 'Silver'
         ELSE 'Bronze'
       END AS tier,
       COUNT(*) AS customers,
       ROUND(AVG(lifetime_spend), 0) AS avg_spend
FROM spend
GROUP BY tier
ORDER BY avg_spend DESC;

-- 11. Months whose revenue beat the average month
WITH monthly AS (
    SELECT DATE_TRUNC('MONTH', o_orderdate) AS order_month,
           SUM(o_totalprice) AS revenue
    FROM orders
    GROUP BY order_month
),
avg_month AS (
    SELECT AVG(revenue) AS avg_revenue FROM monthly
)
SELECT m.order_month, ROUND(m.revenue, 0) AS revenue,
       ROUND(m.revenue - a.avg_revenue, 0) AS above_avg_by
FROM monthly m
CROSS JOIN avg_month a
WHERE m.revenue > a.avg_revenue
ORDER BY m.order_month;

-- 12. Customers who spend more than their nation's average customer
WITH spend AS (
    SELECT c.c_custkey, c.c_name, c.c_nationkey,
           SUM(o.o_totalprice) AS lifetime_spend
    FROM customer c
    JOIN orders o ON o.o_custkey = c.c_custkey
    GROUP BY c.c_custkey, c.c_name, c.c_nationkey
),
nation_avg AS (
    SELECT c_nationkey, AVG(lifetime_spend) AS avg_spend
    FROM spend
    GROUP BY c_nationkey
)
SELECT n.n_name, COUNT(*) AS above_avg_customers
FROM spend s
JOIN nation_avg na ON s.c_nationkey = na.c_nationkey
JOIN nation n      ON s.c_nationkey = n.n_nationkey
WHERE s.lifetime_spend > na.avg_spend
GROUP BY n.n_name
ORDER BY above_avg_customers DESC;

-- ---------------------------------------------------------------------
-- D. Window functions
-- ---------------------------------------------------------------------

-- 13. Number each customer's orders by date (customers 1–3)
SELECT o_custkey, o_orderkey, o_orderdate,
       ROW_NUMBER() OVER (PARTITION BY o_custkey ORDER BY o_orderdate) AS order_seq
FROM orders
WHERE o_custkey IN (1, 2, 4)      -- custkeys divisible by 3 have no orders in TPC-H
ORDER BY o_custkey, order_seq;

-- 14. Top 3 customers by spend in each nation — subquery version
SELECT *
FROM (
    SELECT n.n_name, c.c_name,
           SUM(o.o_totalprice) AS lifetime_spend,
           RANK() OVER (PARTITION BY n.n_name ORDER BY SUM(o.o_totalprice) DESC) AS rnk
    FROM orders o
    JOIN customer c ON o.o_custkey   = c.c_custkey
    JOIN nation   n ON c.c_nationkey = n.n_nationkey
    GROUP BY n.n_name, c.c_name
) t
WHERE rnk <= 3
ORDER BY n_name, rnk;

-- 15. Month-over-month revenue change with LAG
WITH monthly AS (
    SELECT DATE_TRUNC('MONTH', o_orderdate) AS order_month, SUM(o_totalprice) AS revenue
    FROM orders
    GROUP BY order_month
)
SELECT order_month,
       ROUND(revenue, 0) AS revenue,
       ROUND(LAG(revenue) OVER (ORDER BY order_month), 0) AS prev_month,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
                 / LAG(revenue) OVER (ORDER BY order_month), 1) AS pct_change
FROM monthly
ORDER BY order_month;

-- 16. Running (year-to-date) revenue, restarting each year
WITH monthly AS (
    SELECT DATE_TRUNC('MONTH', o_orderdate) AS order_month, SUM(o_totalprice) AS revenue
    FROM orders
    GROUP BY order_month
)
SELECT order_month,
       ROUND(revenue, 0) AS revenue,
       ROUND(SUM(revenue) OVER (PARTITION BY YEAR(order_month) ORDER BY order_month), 0) AS ytd_revenue
FROM monthly
ORDER BY order_month;

-- 17. 3-month moving average
WITH monthly AS (
    SELECT DATE_TRUNC('MONTH', o_orderdate) AS order_month, SUM(o_totalprice) AS revenue
    FROM orders
    GROUP BY order_month
)
SELECT order_month,
       ROUND(revenue, 0) AS revenue,
       ROUND(AVG(revenue) OVER (ORDER BY order_month
                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3m
FROM monthly
ORDER BY order_month;

-- 18. Each region's share of total revenue
SELECT r.r_name AS region,
       ROUND(SUM(o.o_totalprice), 0) AS revenue,
       ROUND(100 * SUM(o.o_totalprice) / SUM(SUM(o.o_totalprice)) OVER (), 1) AS pct_of_total
       -- Snowflake shortcut: 100 * RATIO_TO_REPORT(SUM(o.o_totalprice)) OVER ()
FROM orders o
JOIN customer c ON o.o_custkey   = c.c_custkey
JOIN nation   n ON c.c_nationkey = n.n_nationkey
JOIN region   r ON n.n_regionkey = r.r_regionkey
GROUP BY region
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------
-- E. QUALIFY (filter on window functions, no subquery needed)
-- ---------------------------------------------------------------------

-- 19. Exercise 14 rewritten with QUALIFY
SELECT n.n_name, c.c_name,
       SUM(o.o_totalprice) AS lifetime_spend,
       RANK() OVER (PARTITION BY n.n_name ORDER BY SUM(o.o_totalprice) DESC) AS rnk
FROM orders o
JOIN customer c ON o.o_custkey   = c.c_custkey
JOIN nation   n ON c.c_nationkey = n.n_nationkey
GROUP BY n.n_name, c.c_name
QUALIFY rnk <= 3
ORDER BY n.n_name, rnk;

-- 20. Latest order per customer — the classic de-duplication pattern
SELECT o_custkey, o_orderkey, o_orderdate, o_totalprice
FROM orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY o_custkey
                           ORDER BY o_orderdate DESC, o_orderkey DESC) = 1
ORDER BY o_custkey
LIMIT 20;
-- Tie-breaker (o_orderkey) makes the result deterministic when two orders share a date.
