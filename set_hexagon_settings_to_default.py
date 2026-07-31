#!/usr/bin/env python3
import os
import sys
import json
import django
from django.db import transaction
from django.utils import timezone

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "arches_for_excavation.settings")
sys.path.insert(0, "/arches_app/arches_for_excavation")
django.setup()

from arches.app.models.models import TileModel, ResourceInstance

PAYLOAD = {
  "tileid":"02dd0153-faa4-4016-9207-903cc87a9b73",
  "data":{
    "0e8ffaf5-4148-11e7-b24d-c4b301baab9f":4,
    "0e8ffcab-4148-11e7-a571-c4b301baab9f":"100"
  },
  "nodegroup_id":"0e8ff675-4148-11e7-9c88-c4b301baab9f",
  "parenttile_id":"3442b7e7-9bee-4c54-8d37-eca3a236ef8f",
  "resourceinstance_id":"a106c400-260c-11e7-a604-14109fd34195",
  "provisionaledits":None,
  "sortorder":0
}

def j(x):
  return json.dumps(x, ensure_ascii=False, sort_keys=True)

def die(msg, code=1):
  print(f"❌ {msg}")
  sys.exit(code)

def summarize_tile(t):
  if t is None:
    return None
  return {
    "tileid": str(t.tileid),
    "resourceinstance_id": str(getattr(t, "resourceinstance_id", None) or getattr(t.resourceinstance, "resourceinstanceid", None)),
    "nodegroup_id": str(getattr(t, "nodegroup_id", None)),
    "parenttile_id": str(getattr(t, "parenttile_id", None)),
    "sortorder": getattr(t, "sortorder", None),
    "provisionaledits": t.provisionaledits,
    "data": t.data,
    "data_keys": sorted(list((t.data or {}).keys())),
  }

def diff_data(before_data, after_data):
  before_data = before_data or {}
  after_data = after_data or {}
  keys = sorted(set(before_data.keys()) | set(after_data.keys()))
  changes = []
  for k in keys:
    if before_data.get(k) != after_data.get(k):
      changes.append((k, before_data.get(k), after_data.get(k)))
  return changes

def main():
  print(f"[{timezone.now().isoformat()}] upsert tile start")

  for k in ("tileid", "data", "nodegroup_id", "resourceinstance_id"):
    if k not in PAYLOAD:
      die(f"Missing key in PAYLOAD: {k}")
  if not isinstance(PAYLOAD["data"], dict):
    die("PAYLOAD['data'] must be dict/object")

  tileid = PAYLOAD["tileid"]
  nodegroup_id = PAYLOAD["nodegroup_id"]
  resourceinstance_id = PAYLOAD["resourceinstance_id"]
  parenttile_id = PAYLOAD.get("parenttile_id")

  # resource exists
  ri = ResourceInstance.objects.filter(resourceinstanceid=resourceinstance_id).first()
  if not ri:
    die(f"ResourceInstance not found: {resourceinstance_id}")
  print(f"[check] resource exists: {ri.resourceinstanceid}")

  # parent exists + children count
  if parenttile_id:
    parent = TileModel.objects.filter(tileid=parenttile_id).first()
    if parent:
      print(f"[check] parent tile exists: {parenttile_id} (nodegroup_id={parent.nodegroup_id}, resource={parent.resourceinstance_id})")
      children_qs = TileModel.objects.filter(parenttile_id=parenttile_id)
      print(f"[check] parent children count: {children_qs.count()}")
    else:
      print(f"[warn] parent tile NOT found: {parenttile_id} (UI may be broken)")

  current = TileModel.objects.filter(tileid=tileid).first()
  before = summarize_tile(current)
  print("[before] exists:", bool(current))
  if before:
    print("[before] summary:", j({k: before[k] for k in ("tileid","resourceinstance_id","nodegroup_id","parenttile_id","sortorder")}))
    print("[before] data:", j(before["data"]))

  with transaction.atomic():
    obj = current or TileModel(tileid=tileid)
    created = current is None

    obj.resourceinstance = ri
    obj.nodegroup_id = nodegroup_id
    obj.parenttile_id = parenttile_id
    obj.sortorder = PAYLOAD.get("sortorder", 0)
    obj.provisionaledits = PAYLOAD.get("provisionaledits")
    obj.data = PAYLOAD.get("data") or {}

    obj.save()

  saved = TileModel.objects.get(tileid=tileid)
  after = summarize_tile(saved)

  print("[after] created:", created)
  print("[after] summary:", j({k: after[k] for k in ("tileid","resourceinstance_id","nodegroup_id","parenttile_id","sortorder")}))
  print("[after] data:", j(after["data"]))

  if before:
    dchanges = diff_data(before.get("data"), after.get("data"))
    if dchanges:
      print("[diff] data changes:")
      for k, b, a in dchanges:
        print(f"  - {k}: {b!r} -> {a!r}")
    else:
      print("[diff] data changes: none")
  else:
    print("[diff] tile was created; no 'before' diff")

  # children of THIS tile (if any)
  kids = TileModel.objects.filter(parenttile_id=tileid)
  if kids.exists():
    print(f"[check] this tile children count: {kids.count()}")
    print("[check] first children (up to 10):", [str(x.tileid) for x in kids[:10]])
  else:
    print("[check] this tile children count: 0")

  print(f"[{timezone.now().isoformat()}] upsert tile done ✅")

if __name__ == "__main__":
  main()