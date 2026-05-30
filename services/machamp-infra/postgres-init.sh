#!/usr/bin/env bash
# Runs once on first PostgreSQL initialization (when data dir is empty).
# Creates isolated databases and users for each service.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE USER infisical WITH PASSWORD '${INFISICAL_DB_PASSWORD}';
    CREATE DATABASE infisical OWNER infisical;

    CREATE USER authentik WITH PASSWORD '${AUTHENTIK_DB_PASSWORD}';
    CREATE DATABASE authentik OWNER authentik;
EOSQL
