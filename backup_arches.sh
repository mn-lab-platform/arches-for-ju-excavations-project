#!/usr/bin/env bash
set -euo pipefail

# Load .env (export variables into environment)
source ./.env
# ---- CONFIG ----
BACKUP_DIR="/mnt/storage/arches/arches_data/backups"
DB_CONTAINER="arches_db_dev"
ARCHES_CONTAINER="arches_dev"

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
# Changed source container and path
sudo docker cp "${ARCHES_CONTAINER}:/arches_app/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles" "${BACKUP_DIR}/uploadedfiles_${TS}"
sudo tar -czf "${BACKUP_DIR}/uploadedfiles_${TS}.tar.gz" -C "${BACKUP_DIR}/uploadedfiles_${TS}" .
sudo rm -rf "${BACKUP_DIR}/uploadedfiles_${TS}"

echo "Copying files into cenagis drive 😇😇😇  "
# Fixed variable reference for the dump file (was hardcoded arches_slocal)
cp "${BACKUP_DIR}/${DB_NAME}_${TS}.dump" "/mnt/drive/${DB_NAME}_${TS}.dump"
cp "${BACKUP_DIR}/uploadedfiles_${TS}.tar.gz" "/mnt/drive/uploadedfiles_${TS}.tar.gz"
echo "DONE✅🔥🔥🔥🔥🔥✅✅✅✅✅🔥🔥🔥✅: ${BACKUP_DIR}"

