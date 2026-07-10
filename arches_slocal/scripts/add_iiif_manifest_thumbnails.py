#!/usr/bin/env python3
"""
Add IIIF thumbnail entries to existing Presentation v3 manifests.

By default it scans arches_slocal/uploadedfiles/iiif_raster, where generated
GeoTIFF/photo/RTI manifests live in this project. Thumbnails are not rendered
to disk; they are IIIF Image API URLs such as:

  <service>/full/!300,300/0/default.png
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _first(items: Any) -> Any:
    return items[0] if isinstance(items, list) and items else items


def _service_id_from_canvas(canvas: dict[str, Any]) -> str | None:
    pages = canvas.get("items")
    page = _first(pages)
    annotations = page.get("items") if isinstance(page, dict) else None
    annotation = _first(annotations)
    body = annotation.get("body") if isinstance(annotation, dict) else None
    body = _first(body)

    if not isinstance(body, dict):
        return None

    service = _first(body.get("service"))
    if isinstance(service, dict):
        service_id = service.get("id") or service.get("@id")
        if service_id:
            return str(service_id).rstrip("/")

    body_id = body.get("id") or body.get("@id")
    if isinstance(body_id, str):
        marker = "/full/"
        if marker in body_id:
            return body_id.split(marker, 1)[0].rstrip("/")

    return None


def _thumbnail_url(service_id: str, size: int) -> str:
    return f"{service_id}/full/!{size},{size}/0/default.png"


def _thumbnail_entry(url: str, size: int) -> list[dict[str, Any]]:
    return [{
        "id": url,
        "type": "Image",
        "format": "image/png",
        "width": size,
        "height": size,
    }]


def update_manifest(data: dict[str, Any], size: int, force: bool) -> int:
    if data.get("type") != "Manifest" or not isinstance(data.get("items"), list):
        return 0

    changed = 0
    first_thumbnail: list[dict[str, Any]] | None = None

    for canvas in data["items"]:
        if not isinstance(canvas, dict) or canvas.get("type") != "Canvas":
            continue

        if canvas.get("thumbnail") and not force:
            if first_thumbnail is None and isinstance(canvas.get("thumbnail"), list):
                first_thumbnail = canvas["thumbnail"]
            continue

        service_id = _service_id_from_canvas(canvas)
        if not service_id:
            continue

        thumbnail = _thumbnail_entry(_thumbnail_url(service_id, size), size)
        canvas["thumbnail"] = thumbnail
        if first_thumbnail is None:
            first_thumbnail = thumbnail
        changed += 1

    if first_thumbnail and (force or not data.get("thumbnail")):
        data["thumbnail"] = first_thumbnail
        changed += 1

    return changed


def migrate_manifest(path: Path, size: int, force: bool, dry_run: bool) -> int:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"SKIP invalid JSON: {path} ({exc})")
        return 0

    if not isinstance(data, dict):
        return 0

    changes = update_manifest(data, size=size, force=force)
    if not changes:
        return 0

    print(f"{'WOULD UPDATE' if dry_run else 'UPDATE'} {path} ({changes} thumbnail update(s))")

    if not dry_run:
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(path)

    return changes


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    default_root = project_root / "arches_slocal" / "uploadedfiles" / "iiif_raster"

    parser = argparse.ArgumentParser(
        description="Add IIIF thumbnail fields to existing Presentation v3 manifest JSON files."
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=str(default_root),
        help=f"Directory to scan recursively. Default: {default_root}",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=300,
        help="Maximum thumbnail width/height in pixels. Default: 300.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace existing thumbnail entries.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print files that would be changed without writing them.",
    )
    args = parser.parse_args()

    if args.size <= 0:
        print("--size must be greater than 0")
        return 1

    root = Path(args.root).resolve()
    if not root.exists():
        print(f"Root does not exist: {root}")
        return 1

    total_files = 0
    total_updates = 0

    for path in root.rglob("*.json"):
        updates = migrate_manifest(path, size=args.size, force=args.force, dry_run=args.dry_run)
        if updates:
            total_files += 1
            total_updates += updates

    print(f"Done. Files changed: {total_files}. Thumbnail updates: {total_updates}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
