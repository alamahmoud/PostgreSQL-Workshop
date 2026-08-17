#!/bin/bash
# ============================================================================
# verify_environment.sh — pre-flight check for the Performance & Security lab
# Run before the session to confirm the environment is built correctly.
# Usage: ./verify_environment.sh [database_name]   (default: studentsmis)
# ============================================================================
set -u

DB="${1:-studentsmis}"
PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "==================================================="
echo "Lab 1 (Performance & Security) — Environment Check"
echo "==================================================="

# 1. Service running
if sudo systemctl is-active --quiet postgresql 2>/dev/null \
   || sudo -u postgres pg_isready -q 2>/dev/null; then
    ok "PostgreSQL service is running"
else
    bad "PostgreSQL service is NOT running (sudo systemctl start postgresql)"
fi

# 2. Version
PGVER=$(sudo -u postgres psql -t -A -c "SHOW server_version;" 2>/dev/null | cut -d. -f1)
if [ -n "${PGVER}" ] && [ "${PGVER}" -ge 15 ] 2>/dev/null; then
    ok "PostgreSQL version ${PGVER} (>= 15)"
else
    bad "Could not confirm PostgreSQL version >= 15 (got: '${PGVER}')"
fi

# 3. Database exists
if sudo -u postgres psql -t -A -c \
   "SELECT 1 FROM pg_database WHERE datname='${DB}';" 2>/dev/null | grep -q 1; then
    ok "Database '${DB}' exists"
else
    bad "Database '${DB}' does not exist"
fi

# 4. Expected tables and row counts
for spec in "students:4500" "enrollments:19000" "grades:45000" "courses:90"; do
    T="${spec%%:*}"; MIN="${spec##*:}"
    CNT=$(sudo -u postgres psql -d "${DB}" -t -A -c \
          "SELECT COUNT(*) FROM ${T};" 2>/dev/null)
    if [ -n "${CNT}" ] && [ "${CNT}" -ge "${MIN}" ] 2>/dev/null; then
        ok "Table ${T}: ${CNT} rows (>= ${MIN})"
    else
        bad "Table ${T}: expected >= ${MIN} rows, got '${CNT:-missing}'"
    fi
done

# 5. Lab roles
for ROLE in app_user readonly_user; do
    if sudo -u postgres psql -t -A -c \
       "SELECT 1 FROM pg_roles WHERE rolname='${ROLE}';" 2>/dev/null | grep -q 1; then
        ok "Role '${ROLE}' exists"
    else
        bad "Role '${ROLE}' missing (see Instructor Guide: environment build)"
    fi
done

# 6. Sabotage settings applied (students will fix these)
RPC=$(sudo -u postgres psql -t -A -c "SHOW random_page_cost;" 2>/dev/null)
WM=$(sudo -u postgres psql -t -A -c "SHOW work_mem;" 2>/dev/null)
if [ "${RPC}" = "100" ]; then
    ok "random_page_cost = 100 (intentional lab misconfiguration in place)"
else
    bad "random_page_cost = '${RPC}' (expected 100 — was create_performance_issues.sql run?)"
fi
if [ "${WM}" = "1MB" ]; then
    ok "work_mem = 1MB (intentional lab misconfiguration in place)"
else
    bad "work_mem = '${WM}' (expected 1MB — was create_performance_issues.sql run?)"
fi

# 7. Dead-tuple bloat present
DEAD=$(sudo -u postgres psql -d "${DB}" -t -A -c \
  "SELECT COALESCE(SUM(n_dead_tup),0) FROM pg_stat_user_tables;" 2>/dev/null)
if [ -n "${DEAD}" ] && [ "${DEAD}" -ge 5000 ] 2>/dev/null; then
    ok "Dead tuples present for maintenance exercise (${DEAD})"
else
    bad "Little/no bloat detected (dead tuples: '${DEAD:-0}') — re-run init + issues scripts"
fi

# 8. pg_stat_statements (optional but used by check_performance.sh)
if sudo -u postgres psql -d "${DB}" -t -A -c \
   "SELECT 1 FROM pg_extension WHERE extname='pg_stat_statements';" 2>/dev/null | grep -q 1; then
    ok "pg_stat_statements extension installed"
else
    echo "  [WARN] pg_stat_statements not installed — check_performance.sh will skip that section"
fi

echo "==================================================="
echo "Result: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ] && echo "Environment is READY." || echo "Fix the FAIL items before the session."
exit "${FAIL}"
