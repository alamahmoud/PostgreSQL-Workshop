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
-- Run as:    sudo -u postgres psql -d studentsmis -f create_performance_issues.sql
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
CREATE OR REPLACE FUNCTION find_students_with_multiple_recent_enrollments()
RETURNS TABLE(student_name VARCHAR, enrollment_count BIGINT, total_tuition NUMERIC)
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.student_name,
        COUNT(*) AS enrollment_count,
        SUM(e.tuition_amount) AS total_tuition
    FROM students s
    JOIN enrollments e ON s.student_id = e.student_id
    WHERE EXISTS (
        SELECT 1 FROM enrollments e2
        WHERE e2.student_id = s.student_id
          AND e2.enrollment_date > CURRENT_DATE - INTERVAL '30 days'
    )
    AND EXISTS (
        SELECT 1 FROM enrollments e3
        WHERE e3.student_id = s.student_id
        GROUP BY e3.student_id
        HAVING COUNT(*) > 3
    )
    GROUP BY s.student_name;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- Views with inefficient correlated subqueries (N+1 pattern)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW slow_enrollment_analysis AS
SELECT
    e.enrollment_id,
    e.student_id,
    e.tuition_amount,
    (SELECT COUNT(*)      FROM grades WHERE enrollment_id = e.enrollment_id)     AS grade_count,
    (SELECT SUM(credits)  FROM grades WHERE enrollment_id = e.enrollment_id)     AS total_credits,
    (SELECT student_name  FROM students WHERE student_id = e.student_id)        AS student_name,
    (SELECT COUNT(*)      FROM enrollments e2
      WHERE e2.student_id = e.student_id
        AND e2.enrollment_date < e.enrollment_date)                             AS previous_enrollments
FROM enrollments e
WHERE e.status = 'completed';

CREATE OR REPLACE VIEW slow_student_summary AS
SELECT
    s.*,
    (SELECT COUNT(*)            FROM enrollments e WHERE e.student_id = s.student_id) AS enrollment_count,
    (SELECT SUM(tuition_amount) FROM enrollments e WHERE e.student_id = s.student_id) AS total_tuition,
    (SELECT MAX(enrollment_date) FROM enrollments e WHERE e.student_id = s.student_id) AS last_enrollment,
    (SELECT MIN(enrollment_date) FROM enrollments e WHERE e.student_id = s.student_id) AS first_enrollment,
    (SELECT AVG(tuition_amount) FROM enrollments e WHERE e.student_id = s.student_id) AS avg_tuition_amount
FROM students s;

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
    CASE WHEN random() < 0.5 THEN 'enrollments' ELSE 'students' END,
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
ALTER TABLE enrollments SET (autovacuum_enabled = false);
ALTER TABLE students    SET (autovacuum_enabled = false);
ALTER TABLE grades      SET (autovacuum_enabled = false);

-- ----------------------------------------------------------------------------
-- Deliberately inefficient function: three separate scans instead of one
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_student_lifetime_value(stu_id INTEGER)
RETURNS NUMERIC AS $$
DECLARE
    total               NUMERIC;
    avg_enrollment      NUMERIC;
    enrollment_frequency NUMERIC;
BEGIN
    SELECT SUM(tuition_amount) INTO total
    FROM enrollments WHERE student_id = stu_id;

    SELECT AVG(tuition_amount) INTO avg_enrollment
    FROM enrollments WHERE student_id = stu_id;

    SELECT COUNT(*)::NUMERIC /
           GREATEST(1, EXTRACT(YEAR FROM AGE(MAX(enrollment_date), MIN(enrollment_date))))
    INTO enrollment_frequency
    FROM enrollments WHERE student_id = stu_id;

    RETURN COALESCE(total + (avg_enrollment * enrollment_frequency * 2), 0);
END;
$$ LANGUAGE plpgsql;

-- Reset statistics so students start from a clean slate.
-- NOTE: pg_stat_reset() also zeroes n_dead_tup, which the bloat exercise
-- inspects — so re-ANALYZE afterwards to repopulate the dead-tuple estimates.
SELECT pg_stat_reset();
ANALYZE students;
ANALYZE enrollments;
ANALYZE grades;

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
    DATE_TRUNC('month', enrollment_date) AS month,
    COUNT(*)              AS enrollment_count,
    SUM(tuition_amount)   AS total_tuition,
    AVG(tuition_amount)   AS avg_tuition_amount,
    MIN(tuition_amount)   AS min_tuition_amount,
    MAX(tuition_amount)   AS max_tuition_amount
FROM enrollments
WHERE status = 'completed'
GROUP BY DATE_TRUNC('month', enrollment_date);
-- Intentionally NOT refreshed:
-- REFRESH MATERIALIZED VIEW sales_summary;

-- ----------------------------------------------------------------------------
-- One more analysis view for testing
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW student_enrollment_patterns AS
SELECT
    s.student_id,
    s.student_name,
    COUNT(DISTINCT DATE_TRUNC('month', e.enrollment_date)) AS active_months,
    COUNT(DISTINCT DATE_TRUNC('week',  e.enrollment_date)) AS active_weeks,
    COUNT(e.enrollment_id)   AS total_enrollments,
    AVG(e.tuition_amount)    AS avg_tuition_amount,
    STDDEV(e.tuition_amount) AS tuition_amount_stddev,
    MAX(e.enrollment_date)   AS last_enrollment_date,
    MIN(e.enrollment_date)   AS first_enrollment_date
FROM students s
LEFT JOIN enrollments e ON s.student_id = e.student_id
GROUP BY s.student_id, s.student_name;

COMMENT ON SCHEMA public IS
    'Database intentionally configured with performance issues for training purposes';

SELECT 'Performance issues created. Restart PostgreSQL to apply shared_buffers.' AS status;
