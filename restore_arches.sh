#!/usr/bin/env bash
set -euo pipefail

# ===== Load env (as requested) =====
source ./.env

# ---- CONFIG ----
BACKUP_DIR="../arches_data"
DB_CONTAINER="arches_db"

DB_NAME="${ARCHES_PROJECT}"
DB_USER="${PGUSERNAME}"
DB_PASSWORD="${PGPASSWORD}"

ARCHES_CONTAINER="arches"
TITILER_CONTAINER="titiler"
ARCHES_UPLOADS_DIR="/arches_app/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles"
TITILER_UPLOADS_DIR="/data"
# -----------------

if [[ $# -ne 1 && $# -ne 3 ]]; then
  echo "Usage: $0 <TIMESTAMP> [OLD_DOMAIN NEW_DOMAIN]"
  echo "Example: $0 2026-01-12_1354"
  echo "Example: $0 2026-01-12_1354 https://tap.mn.cenagis.edu.pl http://dev.mn.cenagis.edu.pl"
  exit 1
fi

TS="$1"
DOMAIN_FROM_DEFAULT="https://tap.mn.cenagis.edu.pl"
DOMAIN_TO_DEFAULT="http://dev.mn.cenagis.edu.pl"
DOMAIN_FROM="${2:-$DOMAIN_FROM_DEFAULT}"
DOMAIN_TO="${3:-$DOMAIN_TO_DEFAULT}"
DB_DUMP="${BACKUP_DIR}/${DB_NAME}_${TS}.dump"
UPLOADS_TAR="${BACKUP_DIR}/uploadedfiles_${TS}.tar.gz"
TMP_DIR="${BACKUP_DIR}/_restore_tmp_uploadedfiles_${TS}"

# In Windows Git Bash "sudo" often breaks. Use it only if available and needed.
SUDO=""
if command -v sudo >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

echo "[0/5] Checking containers..."
docker ps --format "{{.Names}}" | grep -qx "${DB_CONTAINER}" || { echo "ERROR: ${DB_CONTAINER} not running"; docker ps; exit 1; }
docker ps --format "{{.Names}}" | grep -qx "${ARCHES_CONTAINER}" || { echo "ERROR: ${ARCHES_CONTAINER} not running"; docker ps; exit 1; }
[[ -f "${DB_DUMP}" ]] || { echo "ERROR: DB dump not found: ${DB_DUMP}"; exit 1; }

# TiTiler mounts the uploads volume read-only at /data. Restore via Arches,
# where the same volume is writable.
TITILER_AVAILABLE=false
if docker ps --format "{{.Names}}" | grep -qx "${TITILER_CONTAINER}"; then
  TITILER_AVAILABLE=true
  echo "TiTiler container found; restored files should be visible at ${TITILER_UPLOADS_DIR}"
else
  echo "TiTiler container not found; uploads will still be restored into Arches"
fi

echo "[1/5] Handling uploads..."
if [ -f "${UPLOADS_TAR}" ]; then
    echo "Extracting uploads archive..."
    ${SUDO} rm -rf "${TMP_DIR}"
    ${SUDO} mkdir -p "${TMP_DIR}"
    tar -xzf "${UPLOADS_TAR}" -C "${TMP_DIR}"
    echo "Top-level in TMP_DIR:"
    ls -lah "${TMP_DIR}" | head -n 30
else
    echo "⚠ Uploads archive not found, skipping extraction"
    TMP_DIR=""
fi

if [ -n "${TMP_DIR}" ]; then
    echo "[2/5] Restoring uploads into shared uploads volume via Arches: ${ARCHES_CONTAINER}:${ARCHES_UPLOADS_DIR}"
    docker exec -u 0 "${ARCHES_CONTAINER}" sh -lc "mkdir -p '${ARCHES_UPLOADS_DIR}' && find '${ARCHES_UPLOADS_DIR}' -mindepth 1 -maxdepth 1 -exec rm -rf {} +"
    docker cp "${TMP_DIR}/." "${ARCHES_CONTAINER}:${ARCHES_UPLOADS_DIR}"
    echo "Fixing permissions inside container..."
    docker exec -u 0 "${ARCHES_CONTAINER}" sh -lc "chown -R arches:arches '${ARCHES_UPLOADS_DIR}' || chmod -R 777 '${ARCHES_UPLOADS_DIR}'"
    echo "Arches uploadedfiles after copy (top-level):"
    docker exec "${ARCHES_CONTAINER}" sh -lc "ls -lah '${ARCHES_UPLOADS_DIR}' | head -n 30"
    if [ "${TITILER_AVAILABLE}" = true ]; then
        echo "TiTiler /data after copy (top-level):"
        docker exec "${TITILER_CONTAINER}" sh -lc "ls -lah '${TITILER_UPLOADS_DIR}' | head -n 30"
    fi
else
    echo "[2/5] Skipping uploads restore (no uploads archive)"
fi

echo "[3/5] Restoring database -> ${DB_NAME}"
DUMP_FILENAME=$(basename "${DB_DUMP}")
CONTAINER_DUMP_PATH="/arches_data/${DUMP_FILENAME}"

echo "  -> Command will use internal path: ${CONTAINER_DUMP_PATH}"

docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" bash -lc \
"pg_restore -U ${DB_USER} -d ${DB_NAME} --clean --if-exists --no-owner --no-acl --verbose ${CONTAINER_DUMP_PATH}"

echo "[4/5] Cleanup temp dir"
[ -n "${TMP_DIR}" ] && ${SUDO} rm -rf "${TMP_DIR}"

echo "[4/5] Reindex Elasticsearch (Arches)"
docker exec "${ARCHES_CONTAINER}" bash -lc "python manage.py es reindex_database"

echo "[5/5] 🔧 Fixing IIIF domains (manifests + iiif_url tiles)"
docker cp fix_domains_full.py "${ARCHES_CONTAINER}:/tmp/fix_domains_full.py"
docker exec "${ARCHES_CONTAINER}" bash -lc \
"python \"/tmp/fix_domains_full.py\" \"${DOMAIN_FROM}\" \"${DOMAIN_TO}\""
docker exec "${ARCHES_CONTAINER}" rm /tmp/fix_domains_full.py

echo "DONE."
echo "Restored:"
echo "  DB:      ${DB_DUMP}"
[ -n "${TMP_DIR}" ] && echo "  Uploads: ${UPLOADS_TAR}" || echo "  Uploads: (skipped)"

 