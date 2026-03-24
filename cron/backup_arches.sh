#!/bin/sh

cd /workdir
echo "Running weekly Arches backup... (`date`)"

dos2unix ./.env 2>/dev/null || true
dos2unix ./backup_arches.sh 2>/dev/null || true

/usr/bin/env bash /workdir/backup_arches.sh