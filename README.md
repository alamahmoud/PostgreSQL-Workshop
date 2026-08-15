# CarvedRock PostgreSQL Workshop

Two hands-on labs for delivering a complete PostgreSQL administration workshop.
Every command, script, and expected output in this package was **executed and
verified on PostgreSQL 16 (Ubuntu 24.04)** during preparation; all commands are
version-parameterized via `$PG_VER` and apply equally to PostgreSQL 15.

## Package contents

```
PostgreSQL-Workshop/
├── README.md                     ← this file
├── AUDIT-REPORT.md               ← every defect found in the source material and its fix
├── Instructor-Guide.docx         ← build checklists, timing, answer key, troubleshooting, resets
├── docker/                       ← one-command student environments (see docker/README.md)
│   ├── docker-compose.yml        (browser portal + CLI profiles lab1 / lab2)
│   ├── Dockerfile                (lab image: Ubuntu 24.04 + apt PostgreSQL, guides' exact layout)
│   ├── entrypoint.sh             (provisions, verifies, drops SYSTEM_COMPLETE marker)
│   ├── systemctl-shim.sh         (guides' systemctl commands work inside the container)
│   ├── portal/                   (browser lab portal: server cards + on-demand terminals)
│   └── README.md                 (browser & CLI quick start, translation table, resets)
├── Lab1-Performance-and-Security/
│   ├── Lab-Guide.docx            ← student guide (2 objectives, 7 tasks)
│   └── lab_files/
│       ├── init_database.sql             (idempotent schema + 20k orders / 50k items + bloat)
│       ├── create_performance_issues.sql (drops indexes, mis-tunes server, disables autovacuum)
│       ├── check_performance.sh          (one-shot health snapshot; auto-detects pg_stat_statements)
│       ├── generate_test_queries.sh      (representative workload generator)
│       └── verify_environment.sh         (13-point pre-flight check)
└── Lab2-Disaster-Recovery-and-Failover/
    ├── Lab-Guide.docx            ← student guide (backups, PITR, replication, failover)
    └── lab_files/
        ├── init_database.sql             (idempotent, deterministic: 10/15/15/21/15 rows)
        └── verify_environment.sh         (9-point pre-flight check)
```

## Suggested delivery order

1. **Lab 1 — Performance & Security** (~60–80 min): EXPLAIN ANALYZE, indexing,
   repairing a hostile server configuration, access hardening, least privilege,
   VACUUM FULL / REINDEX / autovacuum.
2. **Lab 2 — Disaster Recovery & Failover** (~70–90 min): pg_dump/pg_restore,
   WAL archiving, a true point-in-time recovery (post-backup data recovered,
   later disaster excluded), streaming replication, controlled failover.

## Quick start for the trainer

**Browser delivery (recommended):** students need nothing but Docker.

1. `cd docker`
2. `docker compose up -d --build` — builds and starts only the portal
   container itself; this returns in seconds.
3. Open http://localhost:8080 right away — no need to wait. On the very
   first run, the portal builds the shared lab image in the background and
   shows a progress banner (a few minutes, once only); after that, "Open
   terminal" starts working immediately.
4. Click **Open terminal** on a server card. The container is created on
   demand, provisioned, and verified (13/13 for Lab 1, 9/9 for Lab 2) before
   the terminal attaches — the status LED goes *provisioning → ready*. For
   Lab 2, open a terminal on both **pg-primary** and **pg-standby**; they sit
   side by side as tabs.
5. To reset a server between attempts, use the **Reset** button on its card.
6. When finished, tear everything down: `docker compose down` (add
   `--rmi all` to also remove the built images).

**CLI delivery (no portal):** the same compose file supports plain CLI use
via profiles, run from `docker/`:

```bash
# Lab 1
docker compose --profile lab1 up -d --build
docker compose exec -u ubuntu lab1 bash

# Lab 2 (two terminals)
docker compose --profile lab2 up -d --build
docker compose exec -u ubuntu pg-primary bash   # terminal 1
docker compose exec -u ubuntu pg-standby bash   # terminal 2
```

Portal and CLI manage the same containers (`cr-lab1`, `cr-pg-primary`,
`cr-pg-standby`), so they can be mixed freely. Tear down with
`docker compose down` and remove any leftover containers with
`docker rm -f cr-lab1 cr-pg-primary cr-pg-standby`.

Full details, requirements, and the guide-to-Docker translation table:
`docker/README.md`.

**VM delivery:**

1. Read `Instructor-Guide.docx` → *Environment Build* for each lab.
2. Build the images, then run `verify_environment.sh` in each lab's
   `lab_files/` — it must report **all PASS** before students arrive.
3. During delivery, the *Answer Key* and *Troubleshooting* sections of the
   Instructor Guide cover every checkpoint and every failure mode observed
   in testing.
4. Between cohorts, use *Resetting Between Cohorts* — both init scripts are
   idempotent, so a full Lab 1 reset takes under a minute.

## File conventions

* All text files are UTF-8 with **LF** line endings. Do not edit shell scripts
  on Windows without an editor configured for LF — CRLF endings break the
  shebang and heredocs (this exact failure existed in the source material;
  see AUDIT-REPORT.md).
* Shell scripts are executable (`chmod +x`) and accept an optional database
  name argument.
* SQL scripts are safe to re-run at any time.
