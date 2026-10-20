#!/bin/bash

# This script is deliberately idempotent: it runs at every Arches start and
# keeps the reporting account restricted to the five tables it needs.
set -euo pipefail

VERIFY_DB_USER="${VERIFY_DB_USER:-verify_reader}"

if [[ -z "${VERIFY_DB_PASSWORD:-}" ]]; then
    echo "VERIFY_DB_PASSWORD is not set; skipping verification reader setup."
    exit 0
fi

psql_args=(
    --host="${PGHOST}"
    --port="${PGPORT}"
    --user="${PGUSERNAME}"
    -v "verify_user=${VERIFY_DB_USER}"
    -v "verify_password=${VERIFY_DB_PASSWORD}"
)

echo "Configuring PostgreSQL read-only account for verification service..."

# Roles belong to the PostgreSQL cluster, so create/update it through the
# standard postgres database first.
psql "${psql_args[@]}" --dbname=postgres <<'SQL'
\set ON_ERROR_STOP on
SELECT format('CREATE ROLE %I LOGIN', :'verify_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'verify_user') \gexec
SELECT format(
  'ALTER ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',
  :'verify_user', :'verify_password'
) \gexec
SQL

# The grants live in the Arches database and are repeated so a restart repairs
# accidental privilege changes without widening access.
psql "${psql_args[@]}" --dbname="${PGDBNAME}" <<'SQL'
\set ON_ERROR_STOP on
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'verify_user') \gexec
SELECT format('REVOKE ALL ON SCHEMA public FROM %I', :'verify_user') \gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'verify_user') \gexec
SELECT format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', :'verify_user') \gexec
SELECT format('GRANT SELECT ON graphs, nodes, edges, resource_instances, tiles TO %I', :'verify_user') \gexec
SQL
