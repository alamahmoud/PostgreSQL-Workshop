#!/bin/bash
# systemctl shim for the lab containers (no systemd inside Docker).
# Supports exactly what the lab guides use:
#   systemctl start|stop|restart|status postgresql [--no-pager]
# and maps it onto the Debian cluster tooling (pg_ctlcluster).

PG_VER=$(ls /etc/postgresql 2>/dev/null | head -1)
PG_VER=${PG_VER:-16}

CMD=""
for arg in "$@"; do
    case "$arg" in
        -*) ;;                                  # ignore flags like --no-pager
        start|stop|restart|status|is-active) CMD=$arg ;;
        postgresql|postgresql.service|postgresql@*) ;;  # service name
        *) ;;
    esac
done

cluster_online() {
    pg_lsclusters --no-header 2>/dev/null | awk -v v="$PG_VER" \
        '$1==v && $2=="main" {print $4}' | grep -q online
}

case "$CMD" in
    start)
        cluster_online && exit 0
        exec pg_ctlcluster "$PG_VER" main start
        ;;
    stop)
        cluster_online || exit 0
        exec pg_ctlcluster "$PG_VER" main stop
        ;;
    restart)
        if cluster_online; then
            exec pg_ctlcluster "$PG_VER" main restart
        else
            exec pg_ctlcluster "$PG_VER" main start
        fi
        ;;
    status)
        echo "* postgresql.service - PostgreSQL RDBMS (container shim -> pg_ctlcluster $PG_VER main)"
        if cluster_online; then
            echo "     Active: active (running)"
            exit 0
        else
            echo "     Active: inactive (dead)"
            exit 3
        fi
        ;;
    is-active)
        if cluster_online; then echo active; exit 0; else echo inactive; exit 3; fi
        ;;
    *)
        echo "systemctl shim: only start/stop/restart/status of postgresql are supported in the lab container" >&2
        exit 1
        ;;
esac
