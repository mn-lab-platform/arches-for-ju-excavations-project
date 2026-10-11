#!/bin/bash
set -euo pipefail

echo "=== Starting backup daemon... ==="

: "${PGHOST:?PGHOST is required}"
: "${PGUSERNAME:?PGUSERNAME is required}"
: "${PGDBNAME:?PGDBNAME is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD is required}"

echo "Checking Restic repository availability..."
restic snapshots > /dev/null 2>&1 || {
    echo "ERROR: Restic repository is not initialized or unreachable at ${RESTIC_REPOSITORY}." >&2
    echo "Run 'docker compose run --rm backup-daemon restic init' first." >&2
    exit 1
}

DUMP_FILE="/tmp/current_db.dump"

echo "Beginning backup process..."

test -d /uploadedfiles || {
    echo "ERROR: /uploadedfiles is missing." >&2
    exit 1
}

pg_dump -h "${PGHOST}" -U "${PGUSERNAME}" -F c -b -Z 0 "${PGDBNAME}" > "${DUMP_FILE}"

test -s "${DUMP_FILE}"
pg_restore --list "${DUMP_FILE}" > /dev/null

echo "Database dump created: ${DUMP_FILE}"

echo "Backing up Arches media files and database dump into location: ${RESTIC_REPOSITORY}..."

restic --verbose backup /uploadedfiles "${DUMP_FILE}"

echo "Applying backup retention policy..."
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 12

echo "Removing temporary database dump file..."
rm -f "${DUMP_FILE}"

echo "=== Backup process completed successfully! ==="