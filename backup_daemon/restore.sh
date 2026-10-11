#!/bin/bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGUSERNAME:?PGUSERNAME is required}"
: "${PGDBNAME:?PGDBNAME is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD is required}"

if [ -z "${1:-}" ]; then
  echo "Usage: ./restore.sh <snapshot-id>"
  exit 1
fi

SNAPSHOT_ID=$1

if ! restic snapshots > /dev/null 2>&1; then
  echo "ERROR: Restic repository is not initialized or unreachable at ${RESTIC_REPOSITORY}." >&2
  exit 1
fi

if [ ! -d /uploadedfiles ]; then
  echo "ERROR: /uploadedfiles is not mounted." >&2
  exit 1
fi

read -p "Are you sure you want to restore snapshot ${SNAPSHOT_ID}? This action will overwrite both the database and the media files of your Arches application. Proceed? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Restore operation cancelled."
  exit 0
fi

TMP_DIR="/tmp/restore_staging_${SNAPSHOT_ID}"
mkdir -p "${TMP_DIR}"

echo "=== Restoring snapshot from Restic... ==="
restic --verbose restore "${SNAPSHOT_ID}" --target "${TMP_DIR}"

DB_DUMP="${TMP_DIR}/tmp/current_db.dump"
RESTORE_SOURCE="${TMP_DIR}/uploadedfiles"

if [ ! -f "${DB_DUMP}" ]; then
    echo "ERROR: DB dump not found in snapshot at ${DB_DUMP}"
    exit 1
fi

if ! pg_restore --list "${DB_DUMP}" > /dev/null; then
    echo "ERROR: Database dump is invalid or unreadable: ${DB_DUMP}" >&2
    exit 1
fi

if [ ! -d "${RESTORE_SOURCE}" ]; then
    echo "ERROR: Uploads directory not found in snapshot at ${RESTORE_SOURCE}"
    exit 1
fi

echo "Snapshot successfully restored to temporary staging directory: ${TMP_DIR}"

echo "Pushing database dump to PostgreSQL container (${PGHOST})..."

pg_restore -h "${PGHOST}" -U "${PGUSERNAME}" -d "${PGDBNAME}" \
  --clean --if-exists --no-owner --no-acl --verbose "${DB_DUMP}"

echo "Database restore complete."

echo "Restoring media files from staging directory to the application's upload directory..."

echo "Clearing existing media files in the shared volume..."
find /uploadedfiles -mindepth 1 -delete

echo "Copying restored media files..."
cp -a "${RESTORE_SOURCE}/." /uploadedfiles/

echo "Media files restore complete."

echo "Cleaning up temporary staging directory..."
rm -rf "${TMP_DIR}"

echo "=== System rollback completed successfully! ==="