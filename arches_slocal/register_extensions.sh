#!/bin/bash

# Script to automatically register all plugins and reports in Arches
# Run this from the host machine


echo "=== Starting automatic registration of plugins and reports ==="

# Register all plugins/plugins in the plugins folder
echo "Registering plugins..."
PLUGINS_DIR="/arches_app/arches_slocal/arches_slocal/plugins"
if [ -d "$PLUGINS_DIR" ]; then
    echo "Found plugins directory: $PLUGINS_DIR"
    for func_file in "$PLUGINS_DIR"/*; do
        echo "Processing file: $func_file"
        if [ -f "$func_file" ] && [ "$(basename "$func_file")" != "__init__.py" ]; then
            echo "Registering plugin: $func_file"
            python manage.py plugin register --source "$func_file" || echo "Failed to register $func_file"
        fi
    done
else
    echo "plugins directory not found: $PLUGINS_DIR"
fi

# Register all reports in the reports folder
echo "Registering reports..."
REPORTS_DIR="/arches_app/arches_slocal/arches_slocal/reports"
if [ -d "$REPORTS_DIR" ]; then
    for report_file in "$REPORTS_DIR"/*.json; do
        if [ -f "$report_file" ]; then
            echo "Registering report: $report_file"
            python manage.py report register -s "$report_file" || echo "Failed to register $report_file"
        fi
    done
else
    echo "Reports directory not found: $REPORTS_DIR"
fi

echo "=== Registration complete ==="
