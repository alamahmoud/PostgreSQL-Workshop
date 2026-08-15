-- ============================================================================
-- Create Performance Issues for Lab Exercise (Performance & Security Lab)
-- ============================================================================
-- Run AFTER init_database.sql. Deliberately degrades the database so students
-- have realistic problems to diagnose and fix:
--   * drops every non-constraint index
--   * creates inefficient functions and views
--   * disables autovacuum on the busy tables
--   * mis-tunes the server (low memory, no parallelism, hostile planner costs)
--
-- IMPORTANT (instructor): shared_buffers requires a FULL RESTART to take
-- effect. Run once after this script:  sudo systemctl restart postgresql
--
-- Idempotent: safe to re-run.
-- Tested on: PostgreSQL 15 and 16
-- Run as:    sudo -u postgres psql -d carvedrock -f create_performance_issues.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Drop all secondary indexes.
-- Skips primary keys AND indexes that back UNIQUE/EXCLUDE constraints
-- (dropping those directly would fail with a dependency error).
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT ic.relname AS index_name
        FROM pg_index i
        JOIN pg_class ic ON ic.oid = i.indexrelid
        JOIN pg_class tc ON tc.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = tc.relnamespace
        WHERE n.nspname = 'public'
          AND NOT i.indisprimary
          AND NOT EXISTS (
              SELECT 1 FROM pg_constraint con
              WHERE con.conindid = i.indexrelid
          )
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS public.%I', r.index_name);
        RAISE NOTICE 'Dropped index: %', r.index_name;
    END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- Deliberately slow function: correlated EXISTS subqueries with no indexes
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION find_customers_with_multiple_recent_orders()
RETURNS TABLE(customer_name VARCHAR, order_count BIGINT, total_spent NUMERIC)
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.customer_name,
        COUNT(*) AS order_count,
        SUM(o.total_amount) AS total_spent
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE EXISTS (
        SELECT 1 FROM orders o2
        WHERE o2.customer_id = c.customer_id
          AND o2.order_date > CURRENT_DATE - INTERVAL '30 days'
    )
    AND EXISTS (
        SELECT 1 FROM orders o3
        WHERE o3.customer_id = c.customer_id
        GROUP BY o3.customer_id
        HAVING COUNT(*) > 3
    )
    GROUP BY c.customer_name;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Views with inefficient correlated subqueries (N+1 pattern)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW slow_order_analysis AS
SELECT
    o.order_id,
    o.customer_id,
    o.total_amount,
    (SELECT COUNT(*)      FROM order_items WHERE order_id = o.order_id)        AS item_count,
    (SELECT SUM(quantity) FROM order_items WHERE order_id = o.order_id)        AS total_items,
    (SELECT customer_name FROM customers   WHERE customer_id = o.customer_id)  AS customer_name,
    (SELECT COUNT(*)      FROM orders o2
      WHERE o2.customer_id = o.customer_id
        AND o2.order_date < o.order_date)                                      AS previous_orders
FROM orders o
WHERE o.status = 'completed';

CREATE OR REPLACE VIEW slow_customer_summary AS
SELECT
    c.*,
    (SELECT COUNT(*)          FROM orders o WHERE o.customer_id = c.customer_id) AS order_count,
    (SELECT SUM(total_amount) FROM orders o WHERE o.customer_id = c.customer_id) AS total_spent,
    (SELECT MAX(order_date)   FROM orders o WHERE o.customer_id = c.customer_id) AS last_order,
    (SELECT MIN(order_date)   FROM orders o WHERE o.customer_id = c.customer_id) AS first_order,
    (SELECT AVG(total_amount) FROM orders o WHERE o.customer_id = c.customer_id) AS avg_order_value
FROM customers c;

-- ----------------------------------------------------------------------------
-- Audit log table + 1,000 sample rows
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
    audit_id   SERIAL PRIMARY KEY,
    table_name VARCHAR(100),
    operation  VARCHAR(50),
    user_name  VARCHAR(100),
    timestamp  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    old_data   JSONB,
    new_data   JSONB
);

INSERT INTO audit_log (table_name, operation, user_name, old_data, new_data)
SELECT
    CASE WHEN random() < 0.5 THEN 'orders' ELSE 'customers' END,
    CASE WHEN random() < 0.3 THEN 'INSERT'
         WHEN random() < 0.6 THEN 'UPDATE'
         WHEN random() < 0.9 THEN 'SELECT'
         ELSE 'DELETE'
    END,
    'app_user',
    ('{"id": ' || gs || '}')::jsonb,
    ('{"id": ' || gs || ', "modified": true}')::jsonb
FROM generate_series(1, 1000) AS gs;

-- ----------------------------------------------------------------------------
-- Disable autovacuum on the busy tables so bloat persists for the exercise
-- ----------------------------------------------------------------------------
ALTER TABLE orders      SET (autovacuum_enabled = false);
ALTER TABLE customers   SET (autovacuum_enabled = false);
ALTER TABLE order_items SET (autovacuum_enabled = false);

-- ----------------------------------------------------------------------------
-- Deliberately inefficient function: three separate scans instead of one
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_customer_lifetime_value(cust_id INTEGER)
RETURNS NUMERIC AS $$
DECLARE
    total           NUMERIC;
    avg_order       NUMERIC;
    order_frequency NUMERIC;
BEGIN
    SELECT SUM(total_amount) INTO total
    FROM orders WHERE customer_id = cust_id;

    SELECT AVG(total_amount) INTO avg_order
    FROM orders WHERE customer_id = cust_id;

    SELECT COUNT(*)::NUMERIC /
           GREATEST(1, EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))))
    INTO order_frequency
    FROM orders WHERE customer_id = cust_id;

    RETURN COALESCE(total + (avg_order * order_frequency * 2), 0);
END;
$$ LANGUAGE plpgsql;

-- Reset statistics so students start from a clean slate.
-- NOTE: pg_stat_reset() also zeroes n_dead_tup, which the bloat exercise
-- inspects — so re-ANALYZE afterwards to repopulate the dead-tuple estimates.
SELECT pg_stat_reset();
ANALYZE customers;
ANALYZE orders;
ANALYZE order_items;

-- ----------------------------------------------------------------------------
-- Mis-tune the server (students correct these in Objective 1)
--   work_mem 1MB                      -> forces disk-based sorts
--   shared_buffers 32MB               -> minimal caching (RESTART REQUIRED)
--   max_parallel_workers_per_gather 0 -> no parallel query
--   random_page_cost 100              -> planner avoids indexes
-- ----------------------------------------------------------------------------
ALTER SYSTEM SET work_mem = '1MB';
ALTER SYSTEM SET shared_buffers = '32MB';
ALTER SYSTEM SET max_parallel_workers_per_gather = 0;
ALTER SYSTEM SET random_page_cost = 100;

-- Applies the reloadable settings above; shared_buffers still needs a restart.
SELECT pg_reload_conf();

-- ----------------------------------------------------------------------------
-- Stale materialized view (never refreshed — an exercise finding)
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS sales_summary AS
SELECT
    DATE_TRUNC('month', order_date) AS month,
    COUNT(*)          AS order_count,
    SUM(total_amount) AS total_sales,
    AVG(total_amount) AS avg_order_value,
    MIN(total_amount) AS min_order,
    MAX(total_amount) AS max_order
FROM orders
WHERE status = 'completed'
GROUP BY DATE_TRUNC('month', order_date);
-- Intentionally NOT refreshed:
-- REFRESH MATERIALIZED VIEW sales_summary;

-- ----------------------------------------------------------------------------
-- One more analysis view for testing
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW customer_order_patterns AS
SELECT
    c.customer_id,
    c.customer_name,
    COUNT(DISTINCT DATE_TRUNC('month', o.order_date)) AS active_months,
    COUNT(DISTINCT DATE_TRUNC('week',  o.order_date)) AS active_weeks,
    COUNT(o.order_id)      AS total_orders,
    AVG(o.total_amount)    AS avg_order_value,
    STDDEV(o.total_amount) AS order_value_stddev,
    MAX(o.order_date)      AS last_order_date,
    MIN(o.order_date)      AS first_order_date
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.customer_name;

COMMENT ON SCHEMA public IS
    'Database intentionally configured with performance issues for training purposes';

SELECT 'Performance issues created. Restart PostgreSQL to apply shared_buffers.' AS status;
