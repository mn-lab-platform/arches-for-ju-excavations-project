#!/usr/bin/env python3
"""
Update existing IIIF GeoTIFF manifests to request PNG images instead of JPEG.

This preserves transparency for COG-backed IIIF images by replacing:
  - /full/max/0/default.jpg -> /full/max/0/default.png
  - image/jpeg -> image/png

By default it scans arches_slocal/uploadedfiles, where generated manifests live.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


REPLACEMENTS = (
    ("/full/max/0/default.jpg", "/full/max/0/default.png"),
    ("image/jpeg", "image/png"),
)


def update_value(value: Any) -> tuple[Any, int]:
    if isinstance(value, str):
        updated = value
        count = 0
        for old, new in REPLACEMENTS:
            occurrences = updated.count(old)
            if occurrences:
                updated = updated.replace(old, new)
                count += occurrences
        return updated, count

    if isinstance(value, list):
        changed = 0
        updated_items = []
        for item in value:
            updated_item, item_count = update_value(item)
            updated_items.append(updated_item)
            changed += item_count
        return updated_items, changed

    if isinstance(value, dict):
        changed = 0
        updated_dict = {}
        for key, item in value.items():
            updated_item, item_count = update_value(item)
            updated_dict[key] = updated_item
            changed += item_count
        return updated_dict, changed

    return value, 0


def migrate_manifest(path: Path, dry_run: bool) -> int:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"SKIP invalid JSON: {path} ({exc})")
        return 0

    updated, changes = update_value(data)
    if not changes:
        return 0

    print(f"{'WOULD UPDATE' if dry_run else 'UPDATE'} {path} ({changes} replacement(s))")

    if not dry_run:
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(path)

    return changes


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    default_root = project_root / "arches_slocal" / "uploadedfiles"

    parser = argparse.ArgumentParser(
        description="Replace JPEG IIIF image references with PNG in existing manifest JSON files."
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=str(default_root),
        help=f"Directory to scan recursively. Default: {default_root}",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print files that would be changed without writing them.",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Root does not exist: {root}")
        return 1

    total_files = 0
    total_replacements = 0

    for path in root.rglob("*.json"):
        changes = migrate_manifest(path, args.dry_run)
        if changes:
            total_files += 1
            total_replacements += changes

    print(f"Done. Files changed: {total_files}. Replacements: {total_replacements}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
