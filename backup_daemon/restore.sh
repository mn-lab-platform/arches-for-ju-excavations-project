#!/bin/bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGUSERNAME:?PGUSERNAME is required}"
: "${PGDBNAME:?PGDBNAME is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD is required}"

usage() {
  echo "Usage: $0 [-y] <snapshot-id> [all|db|media]"
  echo "  -y        Auto-confirm (non-interactive, safe for 'docker exec -d')"
  echo "  Modes:    all   - restores both DB and uploadedfiles (default)"
  echo "            db    - restores only PostgreSQL database"
  echo "            media - restores only /uploadedfiles"
  exit 1
}

AUTO_CONFIRM=false
while getopts "y" opt; do
  case "$opt" in
    y) AUTO_CONFIRM=true ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

if [ -z "${1:-}" ]; then
  usage
fi

SNAPSHOT_ID=$1
MODE="${2:-all}"

if [[ ! "$MODE" =~ ^(all|db|media)$ ]]; then
  echo "ERROR: Invalid mode '$MODE'. Must be 'all', 'db', or 'media'." >&2
  exit 1
fi

if ! restic snapshots > /dev/null 2>&1; then
  echo "ERROR: Restic repository is not initialized or unreachable at ${RESTIC_REPOSITORY}." >&2
  exit 1
fi

if [[ "$MODE" =~ ^(all|media)$ ]] && [ ! -d /uploadedfiles ]; then
  echo "ERROR: /uploadedfiles is not mounted." >&2
  exit 1
fi

if [ "$AUTO_CONFIRM" = false ]; then
  read -p "Are you sure you want to restore snapshot ${SNAPSHOT_ID} (mode: ${MODE})? Proceed? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Restore operation cancelled."
    exit 0
  fi
fi

if [[ "$MODE" == "all" || "$MODE" == "db" ]]; then
  echo "=== Restoring database dump... ==="

  restic restore "${SNAPSHOT_ID}" --target / --include /tmp/current_db.dump

  DB_DUMP="/tmp/current_db.dump"
  if [ ! -f "${DB_DUMP}" ]; then
      echo "ERROR: DB dump not found in snapshot at ${DB_DUMP}" >&2
      exit 1
  fi

  if ! pg_restore --list "${DB_DUMP}" > /dev/null; then
      echo "ERROR: Database dump is invalid or unreadable: ${DB_DUMP}" >&2
      exit 1
  fi

  echo "Pushing database dump to PostgreSQL container (${PGHOST})..."
  pg_restore -h "${PGHOST}" -U "${PGUSERNAME}" -d "${PGDBNAME}" \
    --clean --if-exists --no-owner --no-acl --verbose "${DB_DUMP}"

  echo "Cleaning up temporary DB dump..."
  rm -f "${DB_DUMP}"
  echo "Database restore complete."
fi

if [[ "$MODE" == "all" || "$MODE" == "media" ]]; then
  echo "=== Restoring media files... ==="

  echo "Clearing existing media files in the shared volume..."
  find /uploadedfiles -mindepth 1 -delete

  echo "Extracting files to /uploadedfiles..."
  restic restore "${SNAPSHOT_ID}" --target / --include /uploadedfiles

  echo "Media files restore complete."
fi

echo "=== System rollback completed successfully! ==="