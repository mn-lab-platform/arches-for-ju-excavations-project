#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
    echo "BŁĄD: uruchom ten skrypt przez sudo: sudo ./reindex_active_resources.sh"
    exit 1
fi

ARCHES_APP_CONTAINER="arches"
ARCHES_DB_CONTAINER="arches_db"
ARCHES_DB_NAME="arches_for_excavation_project"
SYSTEM_SETTINGS_GRAPH_ID="ff623370-fa12-11e6-b98b-6c4008b05c4c"
LEGACY_CONTEXT_GRAPH_ID="d6559924-9f52-11eb-96c4-020063fe0012"
ES_PROCESS_PATTERN='^python manage.py es (delete_indexes|setup_indexes|index_concepts|index_resources_by_type)'
LOCK_FILE="/tmp/arches_for_excavation_reindex_active_resources.lock"
CURRENT_CHILD_PID=""
REINDEX_STARTED=0

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "BŁĄD: inna kopia reindex_active_resources.sh już działa."
    exit 1
fi

stop_indexers() {
    if [[ -n "$CURRENT_CHILD_PID" ]] && kill -0 "$CURRENT_CHILD_PID" 2>/dev/null; then
        kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true
    fi

    pkill -TERM -f "$ES_PROCESS_PATTERN" 2>/dev/null || true
    sleep 2
    pkill -KILL -f "$ES_PROCESS_PATTERN" 2>/dev/null || true
}

on_interrupt() {
    echo
    echo "Przerwano. Zatrzymuję aktywne procesy indeksowania..."
    exit 130
}

cleanup() {
    EXIT_CODE=$?
    trap - EXIT INT TERM HUP

    if (( EXIT_CODE != 0 )); then
        if (( REINDEX_STARTED == 1 )); then
            stop_indexers
        fi
        echo "Reindeks zakończony błędem lub przerwany (kod: $EXIT_CODE)."
    fi

    exit "$EXIT_CODE"
}

trap on_interrupt INT TERM HUP
trap cleanup EXIT

if pgrep -f "$ES_PROCESS_PATTERN" >/dev/null; then
    echo "BŁĄD: wykryto pozostawione procesy Elasticsearch:"
    pgrep -af "$ES_PROCESS_PATTERN"
    echo "Zatrzymaj je przed ponownym uruchomieniem:"
    echo "  sudo pkill -TERM -f '$ES_PROCESS_PATTERN'"
    exit 1
fi

run_tracked() {
    "$@" &
    CURRENT_CHILD_PID=$!
    wait "$CURRENT_CHILD_PID"
    CURRENT_CHILD_PID=""
}

ACTIVE_GRAPH_IDS="$(
    docker exec "$ARCHES_DB_CONTAINER" \
        psql -U postgres -d "$ARCHES_DB_NAME" -tA -c "
            SELECT graphid
            FROM graphs
            WHERE isresource IS TRUE
              AND is_active IS TRUE
              AND publicationid IS NOT NULL
             AND graphid NOT IN (
                 '$SYSTEM_SETTINGS_GRAPH_ID',
                 '$LEGACY_CONTEXT_GRAPH_ID'
             )
            ORDER BY graphid;
        "
)"

if [[ -z "${ACTIVE_GRAPH_IDS//[[:space:]]/}" ]]; then
    echo "BŁĄD: nie znaleziono aktywnych, opublikowanych modeli zasobów."
    exit 1
fi

TOTAL_MODELS="$(printf '%s\n' "$ACTIVE_GRAPH_IDS" | sed '/^$/d' | wc -l)"
echo "Aktywne modele ($TOTAL_MODELS):"
printf '%s\n' "$ACTIVE_GRAPH_IDS"

echo "Odtwarzanie indeksów Elasticsearch..."
REINDEX_STARTED=1
run_tracked docker exec "$ARCHES_APP_CONTAINER" \
    python manage.py es delete_indexes
run_tracked docker exec "$ARCHES_APP_CONTAINER" \
    python manage.py es setup_indexes
run_tracked docker exec "$ARCHES_APP_CONTAINER" \
    python manage.py es index_concepts -b 100 -q

PROCESSED=0
while IFS= read -r GRAPH_ID; do
    [[ -z "$GRAPH_ID" ]] && continue

    CURRENT_NUMBER=$((PROCESSED + 1))
    echo "[$CURRENT_NUMBER/$TOTAL_MODELS] Indeksowanie aktywnego modelu: $GRAPH_ID"

    run_tracked docker exec "$ARCHES_APP_CONTAINER" \
        python manage.py es index_resources_by_type \
        -rt "$GRAPH_ID" \
        -c false \
        -b 100 \
        -q

    PROCESSED=$CURRENT_NUMBER
    echo "[$PROCESSED/$TOTAL_MODELS] OK: $GRAPH_ID"
done <<< "$ACTIVE_GRAPH_IDS"

echo "Gotowe. Zaindeksowano modeli: $PROCESSED/$TOTAL_MODELS"
