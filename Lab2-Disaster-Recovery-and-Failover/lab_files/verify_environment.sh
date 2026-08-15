#!/bin/bash
# ============================================================================
# verify_environment.sh — pre-flight check for the Disaster Recovery lab
# Run on the PRIMARY server before the session.
# Usage: ./verify_environment.sh [database_name]   (default: carvedrock_prod)
# ============================================================================
set -u

DB="${1:-carvedrock_prod}"
PASS=0
FAIL=0

ok()  { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "======================================================"
echo "Lab 2 (Disaster Recovery) — Environment Check (primary)"
echo "======================================================"

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
    bad "Database '${DB}' does not exist (createdb ${DB}, then run init_database.sql)"
fi

# 4. Expected exact row counts (init script is idempotent/deterministic)
for spec in "customers:10" "products:15" "orders:15" "order_items:21" "inventory:15"; do
    T="${spec%%:*}"; WANT="${spec##*:}"
    CNT=$(sudo -u postgres psql -d "${DB}" -t -A -c \
          "SELECT COUNT(*) FROM ${T};" 2>/dev/null)
    if [ "${CNT}" = "${WANT}" ]; then
        ok "Table ${T}: ${CNT} rows"
    else
        bad "Table ${T}: expected ${WANT} rows, got '${CNT:-missing}' — re-run init_database.sql"
    fi
done

# 5. Room for the lab's WAL/backup work
AVAIL=$(df -m /var/backups 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "${AVAIL}" ] && [ "${AVAIL}" -ge 1024 ] 2>/dev/null; then
    ok "/var/backups has ${AVAIL} MB free (>= 1024 MB)"
else
    bad "/var/backups free space low ('${AVAIL:-?}' MB) — backups/archives may fail"
fi

# 6. Informational: current WAL/archive settings (students change these in the lab)
echo "  [INFO] Current settings (students will configure these during the lab):"
sudo -u postgres psql -t -c \
  "SELECT '         wal_level=' || current_setting('wal_level') ||
          ', archive_mode=' || current_setting('archive_mode');" 2>/dev/null

echo "======================================================"
echo "Result: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ] && echo "Environment is READY." || echo "Fix the FAIL items before the session."
exit "${FAIL}"
