# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A packaged, two-lab PostgreSQL administration workshop ("Students MIS"), delivered either via a
browser-based Docker portal or plain Docker CLI. It is not an application with a build/test
pipeline — the "product" is a set of SQL/shell lab scripts, `.docx` guides, and a small Docker
orchestration layer (a Node.js portal + Ubuntu/apt-PostgreSQL image) that gives each student a
disposable, self-verifying Linux+PostgreSQL environment.

- **Lab 1 — Performance & Security** (`Lab1-Performance-and-Security/`): a single sabotaged server
  (`studentsmis` DB) — students diagnose bad planner settings, missing indexes, bloat, and lax
  access control.
- **Lab 2 — Disaster Recovery & Failover** (`Lab2-Disaster-Recovery-and-Failover/`): a primary +
  standby pair (`studentsmis_prod` DB) — students do pg_dump/pg_restore, WAL archiving, a real
  point-in-time recovery, streaming replication, and controlled failover.
- `AUDIT-REPORT.md` documents every defect found in the original source material and its fix —
  read it before touching lab content; several fixes encode non-obvious PostgreSQL behavior (see
  Gotchas below), and reintroducing them is a real risk when editing these files.

## Commands

There is no compiled build, linter, or automated test suite for this repo. "Testing" a change to
lab content means re-running the relevant script(s) end to end and checking output/exit codes.

**Portal (browser delivery, from `docker/`):**
```bash
docker compose up -d --build      # starts only the portal; lab image builds in background on first run
# open http://localhost:8080
docker compose down                # tear down; add --rmi all to also remove built images
```

**CLI delivery (no portal), from `docker/`:**
```bash
docker compose --profile lab1 up -d --build
docker compose exec -u ubuntu lab1 bash

docker compose --profile lab2 up -d --build
docker compose exec -u ubuntu pg-primary bash
docker compose exec -u ubuntu pg-standby bash
```
Portal and CLI drive the same containers (`sm-lab1`, `sm-pg-primary`, `sm-pg-standby`) and can be
mixed. Reset one server with the portal's **Reset** button or `docker rm -f sm-<name>`; state
intentionally lives in the container, not a volume, so reset == recreate.

**Validating a lab environment (run inside the container, or against a VM build):**
```bash
# Lab 1 (13 checks)
bash Lab1-Performance-and-Security/lab_files/verify_environment.sh [db_name]   # default db: studentsmis
bash Lab1-Performance-and-Security/lab_files/check_performance.sh [db_name]
bash Lab1-Performance-and-Security/lab_files/generate_test_queries.sh [db_name]

# Lab 2 (9 checks, run on the primary)
bash Lab2-Disaster-Recovery-and-Failover/lab_files/verify_environment.sh [db_name]  # default db: studentsmis_prod
```
`verify_environment.sh` exits non-zero (count of failed checks) if the environment isn't ready —
this is the closest thing this repo has to a test suite, and is also what
`docker/entrypoint.sh` runs before marking a container ready.

**Re-running the SQL setup directly** (idempotent — safe to re-run; always use `ON_ERROR_STOP=1`
when validating changes, since these scripts must run clean top to bottom):
```bash
sudo -u postgres psql -d studentsmis -q -v ON_ERROR_STOP=1 -f Lab1-Performance-and-Security/lab_files/init_database.sql
sudo -u postgres psql -d studentsmis -q -v ON_ERROR_STOP=1 -f Lab1-Performance-and-Security/lab_files/create_performance_issues.sql
sudo -u postgres psql -d studentsmis_prod -q -v ON_ERROR_STOP=1 -f Lab2-Disaster-Recovery-and-Failover/lab_files/init_database.sql
```

**Portal app (`docker/portal/`)** is a plain Express + dockerode + ws Node app with no test/lint
script defined in `package.json`; `npm install` then `npm start` runs it directly (normally it
only runs inside the `portal` container).

## Architecture

**Docker image (`docker/Dockerfile`) is built on Ubuntu 24.04 + apt PostgreSQL, not the official
`postgres` image**, specifically so paths and service control match what the lab guides describe:
config in `/etc/postgresql/$PG_VER/main`, data in `/var/lib/postgresql/$PG_VER/main`, logs at
`/var/log/postgresql/postgresql-$PG_VER-main.log`, service control via `systemctl`. Since there's
no systemd in the container, `docker/systemctl-shim.sh` is installed as `/usr/local/bin/systemctl`
and translates `start|stop|restart|status postgresql` to `pg_ctlcluster`. This is what lets
students stop the real PostgreSQL service and manipulate the data directory for a genuine PITR
restore, inside a container.

**One shared image, three roles.** All three lab servers (`lab1`, `pg-primary`, `pg-standby`) are
the same image (`studentsmis/pg-lab:1.0`); behavior is selected at first boot by the `LAB_ROLE` env
var, handled entirely in `docker/entrypoint.sh`:
- `lab1` → creates `studentsmis` DB + `app_user`/`readonly_user` roles, loads
  `Lab1.../init_database.sql`, then runs `create_performance_issues.sql` to sabotage it (drops
  indexes, mistunes planner settings, disables autovacuum), restarts PostgreSQL (required for the
  `shared_buffers` change), then runs `verify_environment.sh` and fails the container if it
  doesn't pass.
- `lab2-primary` → creates `studentsmis_prod` DB, loads `Lab2.../init_database.sql` clean (no
  sabotage — students configure archiving/replication themselves), then verifies.
- `lab2-standby` → bare PostgreSQL only; students wipe and clone it from the primary as a lab
  step.

Provisioning runs once, gated by a marker file (`/var/lib/postgresql/.lab_setup_done`); readiness
for external tooling (the portal, `verify_environment.sh`) is signaled by the existence of
`/home/ubuntu/SYSTEM_COMPLETE`. The entrypoint never exits after setup — the container must
survive students deliberately stopping PostgreSQL mid-lab (DR lab), so it tails `/dev/null`
forever instead of tracking the postgres process.

**Portal (`docker/portal/server.js`)** is the browser delivery mechanism: a single Express/ws
server that (1) serves a static SPA (`public/`), (2) drives the Docker socket via `dockerode` to
build the shared lab image on demand (from the package root, ignoring `docker/portal`, `.docx`,
`.zip`, `.git`), create/start/stop/remove the three named containers, and poll each one's
`SYSTEM_COMPLETE` marker for status, and (3) bridges browser WebSockets (`/term?server=<id>`) to
`docker exec -u ubuntu bash -l` PTYs via xterm.js, so terminal I/O flows straight through
Docker's exec API — there is no shell logic in the portal itself. The three servers, their
container names, and their fixed lab-subnet IPs (`172.28.5.0/24`, matching the CIDR the Lab 2
guide has students put in `pg_hba.conf`) are hardcoded in the `SERVERS` map in `server.js` and
must stay in sync with the `docker-compose.yml` service definitions.

**Lab content structure** (per lab, under `lab_files/`): an idempotent `init_database.sql` (drops
and recreates all lab objects — so row counts are always deterministic; Lab 2 is 10/8/15/15/21
students/departments/courses/enrollments/grades rows exactly), a `verify_environment.sh` that is
the pass/fail gate the entrypoint enforces, and lab-specific helper scripts (Lab 1 only:
`create_performance_issues.sql` to sabotage the DB, `check_performance.sh` and
`generate_test_queries.sh` for the performance-diagnosis exercises).

## Gotchas when editing SQL/shell lab files

These are all defects that existed in the original material and were fixed (see
`AUDIT-REPORT.md` for the full list with verification) — the failure modes are non-obvious and
easy to reintroduce:

- **LF line endings only.** CRLF breaks shebangs (`\r: not found` / bad interpreter) and heredoc
  terminators. Don't edit these `.sh`/`.sql` files with a Windows-defaulting editor; verify with
  `file <script>` or by checking for `\r`.
- Shebang must be byte 0 of the file — no leading blank line or whitespace.
- Heredoc terminators (e.g. in `generate_test_queries.sh`) must be an unindented, quoted delimiter
  at column 0 (`<<'EOF'` ... `EOF`), or the heredoc silently swallows the rest of the file.
- plpgsql dollar-quoting is `$$ ... $$`, not `$ ... $`.
- `pg_stat_user_tables`/`pg_stat_user_indexes` expose `relname`/`indexrelname`, not
  `tablename`/`indexname`.
- When dropping "all secondary indexes," exclude indexes backing UNIQUE/EXCLUDE constraints (join
  against `pg_constraint` on `conindid`) — dropping a constraint-owned index directly errors.
- Inserting into a `JSONB` column requires an explicit `::jsonb` cast; string concatenation alone
  produces `text` and errors.
- `shared_buffers` requires a full PostgreSQL **restart** to take effect; `pg_reload_conf()` is
  not sufficient. `autovacuum_enabled` set on a table only matters if the cluster-wide
  `autovacuum_enabled` is also on.
- `pg_stat_reset()` zeroes `n_dead_tup` — if a script relies on dead-tuple stats for a bloat
  exercise, `ANALYZE` the affected tables again after resetting.
- Both `init_database.sql` scripts are drop-and-recreate idempotent by design; don't change them
  to `CREATE TABLE IF NOT EXISTS` + unconditional `INSERT`, which breaks the deterministic row
  counts `verify_environment.sh` depends on.
