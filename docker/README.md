# Running the Workshop with Docker — Browser Portal or CLI

One `docker compose up` gives each student a browser page listing every lab
server. Clicking **Open terminal** creates the container on demand (first
click), provisions it, and attaches a terminal — no Docker knowledge required
from students.

Requirements: Docker Engine 24+ with the Compose plugin, ~2.5 GB free RAM,
~2 GB disk.

## Browser delivery (recommended)

```bash
cd docker
docker compose up -d --build
# open http://localhost:8080
```

`docker compose up -d --build` only builds and starts the portal container
itself, which returns in seconds — open http://localhost:8080 right away,
no need to wait. On the very first run, the portal then builds the shared
lab image in the background: a banner reads "Building the lab image (first
start only, a few minutes) — servers unlock when it finishes," and every
**Open terminal** button stays disabled until it's done. This happens once
ever; on every later `up`, the image already exists and terminals are
available immediately.

What students see and do:

1. A rail of three servers, grouped by lab:
   * **lab1** — Lab 1, sabotaged single server (`172.28.5.20`)
   * **pg-primary** — Lab 2 primary, the guide's "Ubuntu Desktop" (`172.28.5.10`)
   * **pg-standby** — Lab 2 standby, the guide's "Ubuntu Console" (`172.28.5.11`)
2. Click **Open terminal** on a server. If its container doesn't exist yet it
   is created and provisioned right then; the status LED shows
   *provisioning → ready* (ready = the environment verification passed and
   `SYSTEM_COMPLETE` exists — exactly what the guides tell students to wait
   for). Students can watch from inside the terminal with `ls`, as the guides
   describe.
3. For Lab 2, open **two terminal tabs** — one on pg-primary, one on
   pg-standby — and follow the guide. Tabs sit side by side above the
   terminal.
4. **Reset** on a card removes the container; the next *Open terminal*
   recreates it pristine. **Stop**/**Start** map to powering the server off
   and on.

The lab image is Ubuntu 24.04 with PostgreSQL from apt — the same layout the
lab guides use (`/etc/postgresql/$PG_VER/main`, Debian data directories,
`/var/log/postgresql/…`) — plus a `systemctl` shim, so students follow the
guides essentially verbatim, including stopping the server and restoring a
data directory for a real PITR.

## Translating the guides (the complete list)

| Where the guide says | In the portal |
|---|---|
| Open the Ubuntu Desktop / Console from the Connections page | Open terminal on **pg-primary** / **pg-standby** |
| Wait for `SYSTEM_COMPLETE` | identical (`ls`), or watch the status LED |
| `sudo systemctl start/stop/restart/status postgresql` | identical — handled by the shim |
| `PRIMARY_IP` (Lab 2, Task 2.2) | `pg-primary` (Docker DNS) or `172.28.5.10` |
| Replication CIDR `172.31.0.0/16` in pg_hba.conf | `172.28.5.0/24` |
| Reboot the VM | Stop + Start on the card |

Everything else — paths, `$PG_VER`, `sudo -u postgres`, log locations,
`pg_ctlcluster … promote`, expected outputs — is unchanged.

## CLI delivery (no portal)

The same compose file still supports plain CLI use:

```bash
docker compose --profile lab1 up -d --build
docker compose exec -u ubuntu lab1 bash
# Lab 2:
docker compose --profile lab2 up -d --build
docker compose exec -u ubuntu pg-primary bash   # terminal 1
docker compose exec -u ubuntu pg-standby bash   # terminal 2
```

Portal and CLI manage the same containers (`sm-lab1`, `sm-pg-primary`,
`sm-pg-standby`), so they can be mixed freely.

## Reset

| Goal | How |
|---|---|
| Reset one server to pristine | **Reset** button on its card (or `docker rm -f sm-<name>`) |
| Restart a server, state kept | **Stop** then **Start** (or `docker restart sm-<name>`) |
| Tear down everything | `docker compose down` then `docker rm -f sm-lab1 sm-pg-primary sm-pg-standby` |
| Remove images too | add `--rmi all` to the compose down |

State intentionally lives in the containers, not volumes: a reset is one
click, and no stale volume can ever leak a half-broken environment into the
next attempt.

## Notes for the instructor

* **A ready LED means a verified environment.** Provisioning ends by running
  the lab's `verify_environment.sh` (13 checks for Lab 1, 9 for Lab 2); a
  container only drops `SYSTEM_COMPLETE` after all checks pass. If
  provisioning fails, the container exits and `docker logs sm-<name>` names
  the failing check.
* **Security scope:** the portal mounts the Docker socket (that is how it
  creates containers) and has no authentication. It is designed for one
  student per machine on `localhost:8080`, or a trusted classroom LAN behind
  a firewall. **Never expose it to the internet as-is** — anyone reaching the
  page effectively has root on the Docker host. For remote classrooms, put it
  behind a reverse proxy with authentication, or give each student their own
  VM/instance.
* **Multi-student on one shared host** would need per-student container
  prefixes and isolated networks — not included; the intended model is one
  stack per student machine.
* **Offline classrooms:** the portal serves xterm.js locally (no CDN), and
  after the first image build no network is needed at all. To go fully
  offline, pre-pull `ubuntu:24.04` + `node:20-slim` and pre-build both images
  (`docker compose build`), or `docker save`/`load` them.
* **Host ports:** 8080 (portal) plus optional 5432/5433/5434 for host psql
  or GUI tools against CLI-profile containers. Portal-created containers
  publish no ports — students reach PostgreSQL from inside the terminals.
