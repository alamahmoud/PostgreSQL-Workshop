#!/bin/bash
# CarvedRock lab container entrypoint.
# LAB_ROLE selects what gets provisioned on first start:
#   lab1          -> carvedrock DB + roles + pg_stat_statements + sabotage applied
#   lab2-primary  -> carvedrock_prod DB, clean (students configure archiving etc.)
#   lab2-standby  -> bare PostgreSQL only (students wipe & clone it)
set -e

PG_VER=$(ls /etc/postgresql 2>/dev/null | head -1); PG_VER=${PG_VER:-16}
MARKER=/var/lib/postgresql/.lab_setup_done
LOG=/var/log/postgresql/postgresql-$PG_VER-main.log

say() { echo "[lab-setup] $*"; }
as_pg() { cd /tmp && su postgres -c "$*"; }

# ---------------------------------------------------------------- start server
cluster_online() {
    pg_lsclusters --no-header 2>/dev/null | awk -v v="$PG_VER" \
        '$1==v && $2=="main" {print $4}' | grep -q online
}
cluster_online || pg_ctlcluster "$PG_VER" main start
cluster_online || { say "FATAL: cluster failed to start"; tail -n 30 "$LOG"; exit 1; }
say "PostgreSQL $PG_VER cluster 'main' is online."

# ------------------------------------------------------- first-boot provision
if [ ! -f "$MARKER" ]; then
    say "First start — provisioning role: ${LAB_ROLE:-none}"

    # Make the right lab files available where the guides expect them.
    case "${LAB_ROLE:-}" in
        lab1)         SRC=/opt/lab_files/lab1 ;;
        lab2-primary) SRC=/opt/lab_files/lab2 ;;
        *)            SRC="" ;;
    esac
    if [ -n "$SRC" ] && [ -d "$SRC" ]; then
        mkdir -p /home/ubuntu/lab_files
        cp "$SRC"/* /home/ubuntu/lab_files/
        chown -R ubuntu:ubuntu /home/ubuntu/lab_files
        chmod 755 /home/ubuntu/lab_files
        chmod 644 /home/ubuntu/lab_files/*.sql 2>/dev/null || true
        chmod 755 /home/ubuntu/lab_files/*.sh  2>/dev/null || true
        cp "$SRC"/* /tmp/   # postgres-readable copies for setup below
    fi

    case "${LAB_ROLE:-}" in
        lab1)
            as_pg "psql -qc \"ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';\""
            pg_ctlcluster "$PG_VER" main restart
            as_pg "createdb carvedrock"
            as_pg "psql -qc \"CREATE USER app_user PASSWORD 'insecure123';\""
            as_pg "psql -qc \"CREATE USER readonly_user PASSWORD 'readonly123';\""
            as_pg "psql -qc \"GRANT CONNECT ON DATABASE carvedrock TO app_user, readonly_user;\""
            as_pg "psql -d carvedrock -qc 'CREATE EXTENSION pg_stat_statements;'"
            say "Loading schema and data (this is the slow part, ~30-60s) ..."
            as_pg "psql -d carvedrock -q -v ON_ERROR_STOP=1 -f /tmp/init_database.sql"
            say "Applying the deliberate misconfiguration ..."
            as_pg "psql -d carvedrock -q -v ON_ERROR_STOP=1 -f /tmp/create_performance_issues.sql"
            pg_ctlcluster "$PG_VER" main restart   # shared_buffers sabotage needs it
            say "Running environment verification ..."
            bash /home/ubuntu/lab_files/verify_environment.sh || {
                say "VERIFICATION FAILED — see output above"; exit 1; }
            ;;
        lab2-primary)
            as_pg "createdb carvedrock_prod"
            as_pg "psql -d carvedrock_prod -q -v ON_ERROR_STOP=1 -f /tmp/init_database.sql"
            say "Running environment verification ..."
            bash /home/ubuntu/lab_files/verify_environment.sh || {
                say "VERIFICATION FAILED — see output above"; exit 1; }
            ;;
        lab2-standby)
            say "Standby: bare PostgreSQL only — students wipe and clone it."
            ;;
        *)
            say "No LAB_ROLE set — starting bare PostgreSQL."
            ;;
    esac

    rm -f /tmp/*.sql /tmp/*.sh 2>/dev/null || true
    touch "$MARKER"
fi

# ------------------------------------------------------------ ready + stay up
touch /home/ubuntu/SYSTEM_COMPLETE
chown ubuntu:ubuntu /home/ubuntu/SYSTEM_COMPLETE
say "READY. Enter with:  docker compose exec -u ubuntu <service> bash"

# Stream the server log to `docker compose logs`, but never die with the
# server: students intentionally stop PostgreSQL during the DR lab, and the
# container must survive that.
tail -n 0 -F "$LOG" 2>/dev/null &
exec tail -f /dev/null
