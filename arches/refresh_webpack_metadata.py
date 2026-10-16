"""Register installed Arches applications in the generated webpack metadata."""

import importlib.util
import json
import sys
from pathlib import Path


metadata_path = Path(sys.argv[1])
project_app_path = Path(sys.argv[2]).resolve()
if not project_app_path.is_dir():
    raise RuntimeError(f"Cannot locate Arches project application: {project_app_path}")

arches_spec = importlib.util.find_spec("arches")
if arches_spec is None or not arches_spec.submodule_search_locations:
    raise RuntimeError("Cannot locate installed Arches core")
arches_path = Path(next(iter(arches_spec.submodule_search_locations))).resolve()

metadata = (
    json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata_path.is_file()
    else {}
)
metadata.update(
    {
        "_comment": "Generated during the Docker build. Do not edit directly.",
        "APP_RELATIVE_PATH": project_app_path.name,
        "APP_ROOT": str(project_app_path),
        "SITE_PACKAGES_DIRECTORY": str(arches_path.parent),
        "ROOT_DIR": str(arches_path),
        "STATIC_URL": metadata.get("STATIC_URL", "/static/"),
        "WEBPACK_DEVELOPMENT_SERVER_PORT": metadata.get(
            "WEBPACK_DEVELOPMENT_SERVER_PORT", 9000
        ),
    }
)

applications = (
    ("arches_for_excavation", "arches_for_excavation"),
    ("arches_resource_sets", "arches_resource_sets"),
    ("arches_search", "arches_search"),
    ("arches_modular_reports", "arches_modular_reports"),
    ("arches_querysets", "arches.extensions.querysets"),
    ("arches_vue_components", "arches.extensions.vue_components"),
    ("arches_controlled_lists", "arches.extensions.controlled_lists"),
)

metadata["ARCHES_APPLICATIONS"] = [label for label, _ in applications]
paths = metadata.setdefault("ARCHES_APPLICATIONS_PATHS", {})
for label, module in applications:
    spec = importlib.util.find_spec(module)
    if spec is None or not spec.submodule_search_locations:
        raise RuntimeError(f"Cannot locate installed Arches application: {module}")
    paths[label] = str(Path(next(iter(spec.submodule_search_locations))).resolve())

metadata_path.parent.mkdir(parents=True, exist_ok=True)
metadata_path.write_text(json.dumps(metadata, indent=4) + "\n", encoding="utf-8")
