-- =====================================================================
-- Day 1 — Snowsight tour + first queries
-- Repo path suggestion: snowflake-portfolio/learning/day01_snowsight_tour.sql
-- Run top to bottom in a Snowsight worksheet. Read the comments as you go.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Who am I, and what am I using? (context functions)
-- ---------------------------------------------------------------------
SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT(), CURRENT_REGION(),
       CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();

-- ---------------------------------------------------------------------
-- 2. Cost safety first (needs ACCOUNTADMIN).
--    A resource monitor caps credit usage so the trial lasts.
--    (You'll study these properly on Day 12.)
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS TRIAL_GUARD
  WITH CREDIT_QUOTA = 20
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND;

-- ---------------------------------------------------------------------
-- 3. Compute: create your own small warehouse.
--    Compute (warehouses) is separate from storage (databases).
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;   -- best practice: create objects with SYSADMIN, not ACCOUNTADMIN

CREATE WAREHOUSE IF NOT EXISTS DEV_WH
  WITH WAREHOUSE_SIZE = 'XSMALL'
       AUTO_SUSPEND = 60          -- seconds idle before it stops billing
       AUTO_RESUME = TRUE         -- wakes up when a query arrives
       INITIALLY_SUSPENDED = TRUE;

USE ROLE ACCOUNTADMIN;
ALTER WAREHOUSE DEV_WH SET RESOURCE_MONITOR = TRIAL_GUARD;

USE ROLE SYSADMIN;
USE WAREHOUSE DEV_WH;

SHOW WAREHOUSES;   -- note: state, size, auto_suspend, resource_monitor

-- ---------------------------------------------------------------------
-- 4. Storage: object hierarchy is  ACCOUNT > DATABASE > SCHEMA > TABLE/VIEW/STAGE...
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS PORTFOLIO_DB;
CREATE SCHEMA  IF NOT EXISTS PORTFOLIO_DB.SANDBOX;

SHOW DATABASES;
SHOW SCHEMAS IN DATABASE PORTFOLIO_DB;

-- ---------------------------------------------------------------------
-- 5. Sample data. Most trial accounts already have SNOWFLAKE_SAMPLE_DATA.
--    If it's missing from SHOW DATABASES, run these two lines:
-- ---------------------------------------------------------------------
-- USE ROLE ACCOUNTADMIN;
-- CREATE DATABASE SNOWFLAKE_SAMPLE_DATA FROM SHARE SFC_SAMPLES.SAMPLE_DATA;
-- GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE SYSADMIN;
-- USE ROLE SYSADMIN;

-- It's a *shared* database: you query it, but no data was copied into your account.
SHOW SCHEMAS IN DATABASE SNOWFLAKE_SAMPLE_DATA;

USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1;
SHOW TABLES;    -- look at the "rows" and "bytes" columns
DESCRIBE TABLE ORDERS;

-- ---------------------------------------------------------------------
-- 6. First queries (TPC-H: a classic sales star-ish schema)
-- ---------------------------------------------------------------------

-- 6a. Peek at data
SELECT * FROM ORDERS LIMIT 10;

-- 6b. How big is it?
SELECT COUNT(*) AS order_rows FROM ORDERS;
SELECT COUNT(*) AS lineitem_rows FROM LINEITEM;

-- 6c. Orders by status
SELECT o_orderstatus, COUNT(*) AS orders, ROUND(SUM(o_totalprice), 2) AS revenue
FROM ORDERS
GROUP BY o_orderstatus
ORDER BY revenue DESC;

-- 6d. Revenue by region and year (4-table join)
SELECT r.r_name                    AS region,
       YEAR(o.o_orderdate)         AS order_year,
       COUNT(*)                    AS orders,
       ROUND(SUM(o.o_totalprice), 2) AS revenue
FROM ORDERS   o
JOIN CUSTOMER c ON o.o_custkey   = c.c_custkey
JOIN NATION   n ON c.c_nationkey = n.n_nationkey
JOIN REGION   r ON n.n_regionkey = r.r_regionkey
GROUP BY region, order_year
ORDER BY region, order_year;

-- 6e. Top 10 customers by lifetime spend
SELECT c.c_name, c.c_mktsegment, ROUND(SUM(o.o_totalprice), 2) AS lifetime_spend
FROM CUSTOMER c
JOIN ORDERS   o ON o.o_custkey = c.c_custkey
GROUP BY c.c_name, c.c_mktsegment
ORDER BY lifetime_spend DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- 7. See the result cache in action
--    Run 6d again: it should return in milliseconds ("Query result reuse"
--    in Query Profile) and use no warehouse compute.
--    Then disable the cache and run it a third time to compare.
-- ---------------------------------------------------------------------
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
-- (re-run 6d here and compare the duration)
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- Open Query Profile for the slow run: Monitoring > Query History > click the query.
-- Look at: "Partitions scanned" vs "Partitions total", and "Bytes scanned".

-- ---------------------------------------------------------------------
-- 8. Your recent queries, with timing
-- ---------------------------------------------------------------------
SELECT query_text,
       warehouse_name,
       execution_status,
       total_elapsed_time / 1000 AS seconds,
       bytes_scanned
FROM TABLE(PORTFOLIO_DB.INFORMATION_SCHEMA.QUERY_HISTORY())
ORDER BY start_time DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- 9. Done for today: stop paying for compute
-- ---------------------------------------------------------------------
ALTER WAREHOUSE DEV_WH SUSPEND;
