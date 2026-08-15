# Audit Report — Original Lab Material

Review performed from the perspective of a senior PostgreSQL DBA and technical
trainer. Every defect below was **reproduced against a live PostgreSQL 16
instance**, and every fix in this package was **executed and verified** on the
same instance (full PITR cycle, streaming replication, and failover included).

Severity: 🔴 breaks the lab · 🟠 teaches something wrong or silently fails · 🟡 quality/polish

## A. Defects that prevented the labs from running at all

| # | Sev | Location | Defect | Verified impact | Fix |
|---|-----|----------|--------|-----------------|-----|
| A1 | 🔴 | DR `init_database.sql`, Perf `lab/init_database.sql`, `lab/create_performance_issues.sql`, `lab/check_performance.sh` | Literal line numbers embedded in file content (copy-pasted from a numbered editor view), e.g. ` 1 -- CarvedRock…` | `psql -f` fails on the first statement: `ERROR: syntax error at or near "1"` — reproduced. The shell script's shebang is `1 #!/bin/bash`, so it isn't a script at all | All files rewritten clean; executed end-to-end with `ON_ERROR_STOP=1` |
| A2 | 🔴 | Every shipped file | Windows CRLF line endings | Shell scripts fail with `\r: not found` / `bad interpreter` — reproduced | All files are LF; convention documented in README |
| A3 | 🔴 | `check_performance.sh`, `generate_test_queries.sh` (top level) | Leading whitespace before `#!/bin/bash` | Kernel ignores the shebang; script runs under `sh` with CRLF noise — reproduced | Shebang is byte 0 in all scripts |
| A4 | 🔴 | `generate_test_queries.sh` | Heredoc terminator `EOF` indented with spaces (and CRLF) | Delimiter never matches; the heredoc swallows the rest of the file | Rewritten with column-0 quoted delimiter; tested |
| A5 | 🔴 | Perf `lab/init_database.sql` → `slow_customer_report()` | Dollar-quoting written as `$` instead of `$$` (`AS $ … $ LANGUAGE plpgsql`) | Syntax error; function never created | Corrected to `$$`; script now passes `ON_ERROR_STOP=1` |
| A6 | 🔴 | `check_performance.sh` | Queries select `tablename` from `pg_stat_user_tables` and `tablename`/`indexname` from `pg_stat_user_indexes` | Those columns don't exist (they are `relname` / `indexrelname`); two of the four report sections error out | Corrected column names; script output verified |
| A7 | 🔴 | `create_performance_issues.sql` index-drop loop | `DROP INDEX` on every non-`_pkey` index, including indexes that back UNIQUE constraints (`customers_email_key`, `products_sku_key`) | `cannot drop index … because constraint … requires it` aborts the DO block | Loop now joins `pg_index`/`pg_constraint` and skips constraint-owned indexes; uses `format('%I')`; verified — drops exactly the free-standing indexes |
| A8 | 🔴 | `create_performance_issues.sql` audit-log insert | Text expression `'{"id": ' \|\| n \|\| '}'` inserted into a `JSONB` column | `column "old_data" is of type jsonb but expression is of type text` | Explicit `::jsonb` casts; 1,000 rows insert cleanly |

## B. Defects that made the labs teach the wrong thing

| # | Sev | Location | Defect | Verified impact | Fix |
|---|-----|----------|--------|-----------------|-----|
| B1 | 🟠 | Perf lab doc, Objective 1 | The setup script sets `random_page_cost=100` and `max_parallel_workers_per_gather=0`, but the tuning steps never reset them | **Reproduced:** after students create the taught index, the planner still chooses `Seq Scan`; the doc's promised "Bitmap Index Scan / faster execution" cannot occur. The lab's central lesson silently fails | New Task 1.3 diagnoses and resets both settings; re-tested — index is used only after the fix. This is now the lab's explicit teaching moment |
| B2 | 🟠 | DR lab doc, PITR sequence | Recovery target timestamp recorded **before** the "important" inserts; doc itself concedes the restored data "will not include the three orders" | The exercise recovers to a moment when nothing had changed — indistinguishable from a plain base-backup restore. PITR is claimed but never demonstrated | Sequence reordered: backup → good inserts → **record target** → WAL switch → disaster → recover. **Verified live:** log shows `recovery stopping before commit of transaction …`; result is 18 orders = 15 seed + 3 recovered, deletes excluded |
| B3 | 🟠 | DR lab doc, restore steps | Only `base.tar.gz` extracted; `pg_wal.tar.gz` (the WAL streamed during `-Ft` backup) ignored | Recovery depends entirely on the archive being complete; fragile | Guide extracts both tars into place; verified |
| B4 | 🟠 | DR lab doc | Recovery settings written by **overwriting** `postgresql.auto.conf` | Silently destroys any `ALTER SYSTEM` settings captured in the backup (e.g. `shared_preload_libraries`) | Guide **appends** with `tee -a`; rationale explained to students |
| B5 | 🟠 | DR lab doc, replication | `host replication replicator 0.0.0.0/0 md5` | Teaches a world-open HBA rule and legacy md5 in the same line | Guide uses `scram-sha-256` scoped to the lab subnet, with an explicit production note |
| B6 | 🟠 | DR lab doc + init script | `CREATE TABLE IF NOT EXISTS` + unconditional INSERTs, and the doc instructs students to re-run setup and "ignore any errors" | Second run: unique-violation errors on customers/products while orders/items/inventory **double** — hence the doc's otherwise inexplicable expected count of 30 orders | Init script is now drop-and-recreate idempotent; counts are deterministic (10/15/15/21/15) on every run — verified by running it twice. All expected outputs in the guide updated (post-failover: 18/10/15) |
| B7 | 🟠 | Perf lab doc, Objective 2 | `REINDEX TABLE orders/customers` immediately **after** `VACUUM FULL` on the same tables | VACUUM FULL already rebuilds every index on the table; the step is pure redundancy presented as optimization (the doc even hedges that timings "may not be smaller") | Guide states the redundancy explicitly and demonstrates REINDEX on `order_items` (not vacuum-fulled), plus `REINDEX … CONCURRENTLY` production note |
| B8 | 🟠 | Perf lab doc, Objective 2 | Autovacuum thresholds tuned while `autovacuum_enabled=false` (set by the issues script) is still in effect — never re-enabled | Students' "ongoing maintenance" configuration does nothing at all | New Task 2.4 makes discovering `autovacuum_enabled=false` the exercise, then re-enables **and** tunes; verified via `reloptions` |
| B9 | 🟠 | Perf lab doc, password task | Teaches `\password` precisely because it keeps secrets out of history/logs — then verifies with `PGPASSWORD='…' psql` on the command line | Undermines the lesson it just taught | Verification uses `psql -W` (prompt); an explicit caution covers `PGPASSWORD`, `~/.pgpass`, and secret managers |
| B10 | 🟠 | Perf lab doc, logging task | Log path given as `/var/lib/postgresql/$PG_VER/main/log/` | On stock Ubuntu/Debian packaging `logging_collector` is off; logs go to `/var/log/postgresql/postgresql-<ver>-main.log` (the DR lab even uses the correct path) — students find nothing | Correct path primary; `logging_collector` alternative noted with how to check |
| B11 | 🟠 | DR lab doc, post-failover | Promoted standby inherits `archive_mode=on` but the archive directory doesn't exist there | Archiver fails continuously; WAL accumulates unbounded | Final task creates the archive directory on the new primary, with explanation |
| B12 | 🟠 | `create_performance_issues.sql` | Comment claims `pg_reload_conf()` applies all four settings | `shared_buffers` requires restart; on a build that only reloads, the "32MB" sabotage silently isn't active | Comments corrected; Instructor Guide build checklist makes the restart an explicit numbered step |
| B13 | 🟠 | `create_performance_issues.sql` | `pg_stat_reset()` at the end zeroes `n_dead_tup` — the very statistic the bloat exercise inspects | Bloat invisible in `pg_stat_user_tables` despite being physically present — reproduced (verifier initially failed on this) | Script re-`ANALYZE`s the bloated tables after the reset; 13/13 environment checks now pass |

## C. Quality and delivery issues

| # | Sev | Defect | Fix |
|---|-----|--------|-----|
| C1 | 🟡 | Contradictory naming in DR doc: `\l` "shows carved_rock", note says setup ran `CREATE DATABASE carvedrock_prod` | Single consistent name `carvedrock_prod` throughout |
| C2 | 🟡 | Wrong explanation in DR doc: "The chmod -R command recursively changes the owner" | chown (ownership) vs chmod (permissions) explained correctly |
| C3 | 🟡 | Perf doc: "The default shared_buffers should be 25% of RAM" conflates default with recommendation | Reworded: shipped default is conservative (128MB); ~25% of RAM is a common starting point |
| C4 | 🟡 | Editorial leftovers in student docs ("No Windows connection exists, unlike in the screenshot", a pasted web-page header "header-icon / By / 00:58:57"), empty "Expected Output:" placeholders, typos ("VACCUM", "Postgresql") | Documents rebuilt from scratch: numbered steps, consistent command blocks, callouts (Expected output / Why it matters / Note / Caution), headers/footers, verified expected outputs |
| C5 | 🟡 | Structural noise: duplicate `check_performance.sh` at two directory levels; Objective 2 of the perf doc lost all list formatting; hard-coded `15/` paths vs the perf lab's Ubuntu 24.04 (PostgreSQL 16) environment | One canonical `lab_files/` per lab; all paths parameterized with `$PG_VER`; both labs state "tested on 15 and 16" |
| C6 | 🟡 | Random `city`/`state` drawn independently in perf seed data (Denver, TX etc.) | Single random draw selects a consistent city/state pair |
| C7 | 🟡 | Final report template hard-codes marketing numbers ("size reduced by ~40%, performance improved by >90%") | Report reflects the actual actions and measured values from the lab |
| C8 | 🟡 | No environment validation existed; a broken build was only discovered mid-class | New `verify_environment.sh` per lab (13 checks / 9 checks) with named fixes for every FAIL; wired into the Instructor Guide build and reset procedures |
| C9 | 🟡 | No instructor material at all | New Instructor Guide: build checklists, timing, answer-key checkpoints, a 12-row troubleshooting matrix (every entry reproduced or induced during testing), cohort reset procedures, teaching notes |

## What was verified live (PostgreSQL 16.14, Ubuntu 24.04)

* Both init scripts and the issues script under `psql -v ON_ERROR_STOP=1` — zero errors; DR init run twice with identical counts.
* `check_performance.sh` in both modes (with and without `pg_stat_statements`), `generate_test_queries.sh`, both `verify_environment.sh` scripts (all-PASS states reached).
* The B1 failure and fix: index ignored at `random_page_cost=100`, `Bitmap Index Scan` after reset.
* `VACUUM FULL orders`: 11 MB → ~7 MB (matches the guide's expected output).
* Full PITR cycle: archiving → base backup → marker inserts → target after inserts → WAL switch → destructive delete → restore both tars → append recovery config → `recovery stopping before commit` → 18 orders with all 3 markers recovered, new timeline.
* Full replication + failover cycle: scram-authenticated `pg_basebackup -R -X stream`, `pg_stat_replication` streaming, rows visible on standby, promote, `pg_is_in_recovery()=f`, post-failover writes, integrity counts 18/10/15.

*Not exercised in the sandbox:* the hosted-lab UI steps (Connections page, SYSTEM_COMPLETE marker) and true two-host networking — replication was validated with two clusters on one host, which exercises identical PostgreSQL code paths.
