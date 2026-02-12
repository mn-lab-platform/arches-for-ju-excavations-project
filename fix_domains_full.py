#!/usr/bin/env python
"""
Complete domain migration script for IIIF manifests and tiles.

Updates:
1. IIIFManifest objects (manifest JSON)
2. Tiles containing iiif_url values

Usage: 
  python fix_domains_full.py <old_domain> <new_domain>

Example:
  python fix_domains_full.py https://tap.mn.cenagis.edu.pl http://localhost:8000
"""

import os
import sys
import django
import json

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'arches_slocal.settings')
sys.path.insert(0, '/arches_app/arches_slocal')
django.setup()

from arches.app.models.models import IIIFManifest, TileModel

def update_manifests(old_domain, new_domain):
    """Update all IIIFManifest objects"""
    updated = 0
    manifests = IIIFManifest.objects.all()
    
    print(f"\n[1/2] Updating {manifests.count()} IIIF Manifests...")
    print(f"         Replacing: {old_domain} -> {new_domain}")
    
    for m in manifests:
        manifest_str = json.dumps(m.manifest)
        original = manifest_str
        
        # Only replace the production domain
        manifest_str = manifest_str.replace(old_domain, new_domain)
        
        if manifest_str != original:
            m.manifest = json.loads(manifest_str)
            m.save()
            updated += 1
            print(f"  ✅ Updated manifest: {m.globalid}")
        else:
            print(f"  ⏭️  No changes: {m.globalid}")
    
    print(f"\n  Total manifests updated: {updated}/{manifests.count()}")
    return updated

def _replace_in_url(value, old_domain, new_domain):
    """
    Supports:
    - plain string
    - language-wrapped dict: {"en": {"value": "...", "direction": "ltr"}}
    """
    if isinstance(value, str):
        return value.replace(old_domain, new_domain)
    if isinstance(value, dict):
        changed = False
        new_dict = {}
        for lang, payload in value.items():
            if isinstance(payload, dict) and "value" in payload:
                new_payload = dict(payload)
                new_payload["value"] = payload["value"].replace(old_domain, new_domain)
                changed = changed or new_payload["value"] != payload["value"]
                new_dict[lang] = new_payload
            else:
                new_dict[lang] = payload
        return new_dict if changed else value
    return value

def update_tiles(old_domain, new_domain, iiif_url_node_id='e0216dc7-89ba-4a27-9126-bf7e06d859a8'):
    """Update all tiles containing iiif_url"""
    updated = 0
    tiles = TileModel.objects.filter(data__has_key=iiif_url_node_id)
    print(f"\n[2/2] Updating {tiles.count()} tiles with iiif_url...")
    print(f"         Replacing: {old_domain} -> {new_domain}")
    for tile in tiles:
        tile_data = tile.data
        original_url = tile_data.get(iiif_url_node_id)
        if original_url is None:
            continue
        modified = _replace_in_url(original_url, old_domain, new_domain)
        if modified != original_url:
            tile_data[iiif_url_node_id] = modified
            tile.data = tile_data
            tile.save()
            updated += 1
            print(f"  ✅ Updated tile {tile.tileid}")
    print(f"\n  Total tiles updated: {updated}/{tiles.count()}")
    return updated

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    
    old_domain = sys.argv[1].rstrip('/')
    new_domain = sys.argv[2].rstrip('/')
    
    print("="*60)
    print("IIIF Domain Migration Script")
    print("="*60)
    print(f"Old domain: {old_domain}")
    print(f"New domain: {new_domain}")
    print(f"\nNote: Cantaloupe internal URLs are left unchanged")
    print(f"      (they are normalized by JavaScript)")
    
    try:
        manifest_count = update_manifests(old_domain, new_domain)
        tile_count = update_tiles(old_domain, new_domain)
        
        print("\n" + "="*60)
        print("✅ Migration Complete!")
        print("="*60)
        print(f"Manifests updated: {manifest_count}")
        print(f"Tiles updated: {tile_count}")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)