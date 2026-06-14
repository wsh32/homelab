#!/usr/bin/env bash
# Runs once on first PostgreSQL initialization (when data dir is empty).
# Creates isolated databases and users for each service.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE infisical;

    CREATE USER authentik WITH PASSWORD '${AUTHENTIK_DB_PASSWORD}';
    CREATE DATABASE authentik OWNER authentik;
EOSQL

# Authentik requires pg_trgm and pg_crypto extensions in its database.
# Must be created as superuser before migrations run.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname authentik <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
EOSQL
