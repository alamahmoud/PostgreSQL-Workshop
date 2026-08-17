#!/bin/bash
# ============================================================================
# check_performance.sh — snapshot of current database performance metrics
# Usage: ./check_performance.sh [database_name]   (default: studentsmis)
# Tested on: PostgreSQL 15 and 16
# ============================================================================
set -u

DB="${1:-studentsmis}"
PSQL="sudo -u postgres psql -d ${DB} -v ON_ERROR_STOP=0"

echo "==================================="
echo "PostgreSQL Performance Check"
echo "Database: ${DB}"
echo "==================================="
echo ""

# --- Database size -----------------------------------------------------------
echo "Database Size:"
$PSQL -t -c "SELECT pg_size_pretty(pg_database_size('${DB}'));"
echo ""

# --- Table sizes and bloat ---------------------------------------------------
# pg_stat_user_tables exposes relname (not tablename).
echo "Table Sizes and Bloat:"
$PSQL -x -c "
SELECT
    schemaname,
    relname,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) AS size,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    CASE
        WHEN n_live_tup > 0
        THEN round(n_dead_tup * 100.0 / n_live_tup, 2)
        ELSE 0
    END AS dead_percentage
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC;"
echo ""

# --- Slowest queries (requires pg_stat_statements) ---------------------------
echo "Slowest Queries (from pg_stat_statements):"
HAS_PSS=$($PSQL -t -A -c \
  "SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements';")
if [ "${HAS_PSS}" = "1" ]; then
    $PSQL -c "
SELECT
    substr(query, 1, 60)                  AS query_preview,
    calls,
    round(mean_exec_time::numeric, 2)     AS avg_ms,
    round(total_exec_time::numeric, 2)    AS total_ms
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY mean_exec_time DESC
LIMIT 5;"
else
    echo "  [skipped] pg_stat_statements is not installed in ${DB}."
    echo "  To enable it:"
    echo "    1. Add to postgresql.conf:  shared_preload_libraries = 'pg_stat_statements'"
    echo "    2. Restart PostgreSQL:      sudo systemctl restart postgresql"
    echo "    3. In the database run:     CREATE EXTENSION pg_stat_statements;"
fi
echo ""

# --- Index usage -------------------------------------------------------------
# pg_stat_user_indexes exposes relname / indexrelname (not tablename / indexname).
echo "Index Usage Statistics:"
$PSQL -c "
SELECT
    schemaname,
    relname,
    indexrelname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan
LIMIT 10;"
echo ""

# --- Key configuration -------------------------------------------------------
echo "Current Configuration (performance-relevant):"
$PSQL -c "
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('shared_buffers','work_mem','effective_cache_size',
               'random_page_cost','max_parallel_workers_per_gather')
ORDER BY name;"
echo ""

echo "Performance check complete."
