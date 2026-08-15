# CarvedRock PostgreSQL Workshop — shared lab image
#
# Deliberately built on Ubuntu + apt PostgreSQL (not the official postgres
# image) so the container matches the lab guides byte for byte:
#   - config in /etc/postgresql/$PG_VER/main
#   - data   in /var/lib/postgresql/$PG_VER/main
#   - logs   in /var/log/postgresql/postgresql-$PG_VER-main.log
#   - service control via a systemctl shim -> pg_ctlcluster
# This is what lets students stop the server, move the data directory,
# and perform a real PITR restore *inside* a running container.
#
# Build context is the PACKAGE ROOT (see docker-compose.yml), so the lab
# files are baked into the image and containers are fully self-contained —
# the browser portal can create them with no host bind mounts.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql postgresql-contrib \
        sudo less nano vim-tiny procps iputils-ping ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The ubuntu user (uid 1000) ships with the 24.04 base image; the guides
# assume it exists with passwordless sudo, like the original lab VMs.
RUN echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && chmod 755 /home/ubuntu

# No systemd in a container: a thin shim makes the guides' systemctl
# commands (start/stop/restart/status postgresql) work unchanged.
COPY docker/systemctl-shim.sh /usr/local/bin/systemctl
COPY docker/entrypoint.sh     /usr/local/bin/lab-entrypoint.sh
RUN chmod 755 /usr/local/bin/systemctl /usr/local/bin/lab-entrypoint.sh

# Lab files baked in, selected by LAB_ROLE at first start.
COPY Lab1-Performance-and-Security/lab_files/      /opt/lab_files/lab1/
COPY Lab2-Disaster-Recovery-and-Failover/lab_files/ /opt/lab_files/lab2/
RUN chmod -R a+rX /opt/lab_files

EXPOSE 5432
ENTRYPOINT ["/usr/local/bin/lab-entrypoint.sh"]
