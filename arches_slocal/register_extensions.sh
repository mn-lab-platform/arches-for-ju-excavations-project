#!/bin/bash

APP_ROOT=${APP_ROOT}
ARCHES_PROJECT=${ARCHES_PROJECT}

PLUGINS_DIR="${APP_ROOT}/${ARCHES_PROJECT}/plugins"
REPORTS_DIR="${APP_ROOT}/${ARCHES_PROJECT}/reports"
echo "Using plugins directory: $PLUGINS_DIR"
echo "Using reports directory: $REPORTS_DIR"

echo "=== Starting automatic registration of plugins and reports ==="

echo "Checking for plugins in: $PLUGINS_DIR"
if [ -d "$PLUGINS_DIR" ]; then
    for func_file in "$PLUGINS_DIR"/*; do
        if [ -f "$func_file" ] && [ "$(basename "$func_file")" != "__init__.py" ]; then
            output=$(python manage.py plugin register --source "$func_file" 2>&1)
            exit_code=$?

            if [ $exit_code -eq 0 ]; then
                echo "Successfully registered plugin: $(basename "$func_file")"
            else
                if echo "$output" | grep -q 'duplicate key value violates unique constraint'; then
                    echo "Skipped plugin (already exists): $(basename "$func_file")"
                else
                    echo "Failed to register plugin: $(basename "$func_file")"
                    echo "Error details:"
                    echo "$output"
                fi
            fi
        fi
    done
else
    echo "Plugins directory not found: $PLUGINS_DIR"
fi

echo "---------------------------------------------------------------"

# ---------------------------------------------------------
# 2. Register Reports
# ---------------------------------------------------------
echo "Checking for reports in: $REPORTS_DIR"
if [ -d "$REPORTS_DIR" ]; then
    for report_file in "$REPORTS_DIR"/*.json; do
        if [ -f "$report_file" ]; then
            
            output=$(python manage.py report register -s "$report_file" 2>&1)
            exit_code=$?

            if [ $exit_code -eq 0 ]; then
                echo "Successfully registered report: $(basename "$report_file")"
            else
                if echo "$output" | grep -q 'duplicate key value violates unique constraint'; then
                    echo "Skipped report (already exists): $(basename "$report_file")"
                else
                    echo "Failed to register report: $(basename "$report_file")"
                    echo "Error details:"
                    echo "$output"
                fi
            fi
        fi
    done
else
    echo "Reports directory not found: $REPORTS_DIR"
fi

echo "=== Registration complete ==="