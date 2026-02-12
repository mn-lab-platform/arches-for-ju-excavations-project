#!/usr/bin/env bash
set -euo pipefail

# Load .env (export variables into environment)
source ./.env
# ---- CONFIG ----
BACKUP_DIR="/mnt/storage/arches/arches_data/backups"
DB_CONTAINER="arches_db"

# From .env / your setup:
DB_NAME="${ARCHES_PROJECT}"
DB_USER="${PGUSERNAME}"
DB_PASSWORD="${PGPASSWORD}"
# --------------
TS="$(date +%F_%H%M)"
mkdir -p "${BACKUP_DIR}"

echo "[1/2]🧠 DB dump -> ${BACKUP_DIR}/${DB_NAME}_${TS}.dump"
sudo docker exec -e PGPASSWORD="${DB_PASSWORD}" "${DB_CONTAINER}" \
  pg_dump -U "${DB_USER}" -F c -b -Z 6 "${DB_NAME}" \
  > "${BACKUP_DIR}/${DB_NAME}_${TS}.dump"

echo "[2/2] 🧠Uploaded files volume -> ${BACKUP_DIR}/uploadedfiles_${TS}.tar.gz"
sudo docker cp cantaloupe_arches_slocal:/imageroot/uploadedfiles "${BACKUP_DIR}/uploadedfiles_${TS}"
sudo tar -czf "${BACKUP_DIR}/uploadedfiles_${TS}.tar.gz" -C "${BACKUP_DIR}/uploadedfiles_${TS}" .
sudo rm -rf "${BACKUP_DIR}/uploadedfiles_${TS}"
echo "Copying files into cenagis drive 😇😇😇  "
cp arches_data/backups/arches_slocal_${TS}.dump /mnt/drive/arches_slocal_${TS}.dump
cp arches_data/backups/uploadedfiles_${TS}.tar.gz /mnt/drive/uploadedfiles_${TS}.tar.gz
echo "DONE✅🔥🔥🔥🔥🔥✅✅✅✅✅🔥🔥🔥✅: ${BACKUP_DIR}"
