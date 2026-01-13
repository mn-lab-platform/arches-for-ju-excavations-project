#!/usr/bin/env bash
set -euo pipefail

# ===== Load env (as requested) =====
source ./.env

# ---- CONFIG ----
BACKUP_DIR="../arches_data/backups"
DB_CONTAINER="arches_db"

DB_NAME="${ARCHES_PROJECT}"
DB_USER="${PGUSERNAME}"
DB_PASSWORD="${PGPASSWORD}"

ARCHES_CONTAINER="arches"
CANTALOUPE_CONTAINER="cantaloupe_arches_slocal"
# -----------------

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <TIMESTAMP>"
  echo "Example: $0 2026-01-12_1354"
  exit 1
fi

TS="$1"
DB_DUMP="${BACKUP_DIR}/${DB_NAME}_${TS}.dump"
UPLOADS_TAR="${BACKUP_DIR}/uploadedfiles_${TS}.tar.gz"
TMP_DIR="${BACKUP_DIR}/_restore_tmp_uploadedfiles_${TS}"

# ---- Validation ----
[[ -f "${DB_DUMP}" ]] || { echo "ERROR: DB dump not found: ${DB_DUMP}"; exit 1; }
[[ -f "${UPLOADS_TAR}" ]] || { echo "ERROR: Uploads archive not found: ${UPLOADS_TAR}"; exit 1; }

# In Windows Git Bash "sudo" often breaks. Use it only if available and needed.
SUDO=""
if command -v sudo >/dev/null 2>&1; then
  # If sudo works without prompting, keep it; otherwise skip it.
  if sudo -n true >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

echo "[0/5] Checking containers..."
docker ps --format "{{.Names}}" | grep -qx "${DB_CONTAINER}" || { echo "ERROR: ${DB_CONTAINER} not running"; docker ps; exit 1; }
docker ps --format "{{.Names}}" | grep -qx "${CANTALOUPE_CONTAINER}" || { echo "ERROR: ${CANTALOUPE_CONTAINER} not running"; docker ps; exit 1; }
docker ps --format "{{.Names}}" | grep -qx "${ARCHES_CONTAINER}" || { echo "ERROR: ${ARCHES_CONTAINER} not running"; docker ps; exit 1; }

echo "[1/5] Unpacking uploads on host -> ${TMP_DIR}"
${SUDO} rm -rf "${TMP_DIR}"
${SUDO} mkdir -p "${TMP_DIR}"
${SUDO} tar -xzf "${UPLOADS_TAR}" -C "${TMP_DIR}"

echo "Top-level in TMP_DIR:"
ls -lah "${TMP_DIR}" | head -n 30

echo "[2/5] Restoring uploads into Cantaloupe: ${CANTALOUPE_CONTAINER}:/imageroot/uploadedfiles"

# --- POPRAWKA: 'Device or resource busy' ---
# Folder /imageroot/uploadedfiles jest wolumenem (zamontowany), więc nie można go usunąć.
# Zamiast tego usuwamy całą jego ZAWARTOŚĆ używając gwiazdki (*).
# "|| true" na końcu zapobiega błędom, jeśli folder jest już pusty.
docker exec -u 0 "${CANTALOUPE_CONTAINER}" sh -lc "rm -rf /imageroot/uploadedfiles/* || true"

docker cp "${TMP_DIR}/." "${CANTALOUPE_CONTAINER}:/imageroot/uploadedfiles"

# Fixing permissions inside container...
# (Ustawiamy uprawnienia, bo po 'docker cp' pliki mogą należeć do roota, a Cantaloupe ich nie odczyta)
echo "Fixing permissions inside container..."
docker exec -u 0 "${CANTALOUPE_CONTAINER}" sh -lc "chown -R arches:arches /imageroot/uploadedfiles || chmod -R 777 /imageroot/uploadedfiles"

echo "Cantaloupe uploadedfiles after copy (top-level):"
docker exec "${CANTALOUPE_CONTAINER}" sh -lc "ls -lah /imageroot/uploadedfiles | head -n 30"

echo "[3/5] Restoring database -> ${DB_NAME}"

# 1. Wyciągamy samą nazwę pliku z pełnej ścieżki (np. "arches_slocal_2026...dump")
DUMP_FILENAME=$(basename "${DB_DUMP}")

# 2. Budujemy ścieżkę, pod którą kontener widzi ten plik (bazując na Twoim ręcznym teście)
CONTAINER_DUMP_PATH="/arches_data/backups/${DUMP_FILENAME}"

echo "  -> Command will use internal path: ${CONTAINER_DUMP_PATH}"

# 3. Uruchamiamy pg_restore wskazując plik wewnątrz kontenera
# Używamy bash -lc, tak jak w Twoim działającym przykładzie
docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" bash -lc \
"pg_restore -U ${DB_USER} -d ${DB_NAME} --clean --if-exists --no-owner --no-acl --verbose ${CONTAINER_DUMP_PATH}"
echo "[4/5] Cleanup temp dir"
${SUDO} rm -rf "${TMP_DIR}"

echo "[5/5] Reindex Elasticsearch (Arches)"
# Avoid -it (TTY) to prevent Git Bash issues; run non-interactive
docker exec "${ARCHES_CONTAINER}" bash -lc "python manage.py es reindex_database"

echo "DONE."
echo "Restored:"
echo "  DB:      ${DB_DUMP}"
echo "  Uploads: ${UPLOADS_TAR}"
