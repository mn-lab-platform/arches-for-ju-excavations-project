#!/bin/bash

echo "=== Starting automatic registration of plugins, reports, and functions ==="

ARCHES_FOR_EXCAVATION_DIR=$(python -c "import arches_for_excavation, os; print(os.path.dirname(arches_for_excavation.__file__))")

PLUGINS_DIR="${ARCHES_FOR_EXCAVATION_DIR}/plugins"
REPORTS_DIR="${ARCHES_FOR_EXCAVATION_DIR}/reports"
FUNCTIONS_DIR="${ARCHES_FOR_EXCAVATION_DIR}/functions"

echo "Using plugins directory: $PLUGINS_DIR"
echo "Using reports directory: $REPORTS_DIR"
echo "Using functions directory: $FUNCTIONS_DIR"

# ---------------------------------------------------------
# 1. Register Plugins
# ---------------------------------------------------------
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

echo "---------------------------------------------------------------"

# ---------------------------------------------------------
# 3. Register Functions
# ---------------------------------------------------------
echo "Checking for functions in: $FUNCTIONS_DIR"
if [ -d "$FUNCTIONS_DIR" ]; then
    for function_file in "$FUNCTIONS_DIR"/*.py; do
        if [ -f "$function_file" ] && [ "$(basename "$function_file")" != "__init__.py" ]; then
            
            output=$(python manage.py fn register --source "$function_file" 2>&1)
            exit_code=$?

            if [ $exit_code -eq 0 ]; then
                echo "Successfully registered function: $(basename "$function_file")"
            else
                if echo "$output" | grep -q 'duplicate key value violates unique constraint'; then
                    echo "Skipped function (already exists): $(basename "$function_file")"
                else
                    echo "Failed to register function: $(basename "$function_file")"
                    echo "Error details:"
                    echo "$output"
                fi
            fi
        fi
    done
else
    echo "Functions directory not found: $FUNCTIONS_DIR"
fi

echo "=== Registration complete ==="