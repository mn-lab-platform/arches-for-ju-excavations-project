#!/usr/bin/env python3
import os
import sys
import csv
import traceback
import django
import uuid

# ==========================================
#               CONFIGURATION
# ==========================================
LOCAL_CSV_PATH = "/arches_data/sf_points_local.csv"
WGS84_CSV_PATH = "/arches_data/sf_points_wgs84.csv"

# Node IDs from the new model
POSITION_GEOJSON_NODE_ID = 'bbdde26b-edb0-4f14-ba56-11d9a4296800'  # Position - geojson
MEASUREMENT_TXT_NODE_ID = 'd7baaa04-3f55-40ac-99ce-2c42bcf66d10'   # Measurement (txt)
# ==========================================

# Setup Django Environment
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "arches_for_excavation_project.settings")
sys.path.insert(0, "/arches_app/arches_for_excavation_project")
django.setup()

from arches.app.models.tile import Tile
from arches.app.models.models import Node, NodeGroup
from arches.app.models.resource import Resource

def create_geojson_point(lon, lat, z, node_id):
    """Generates a standard Arches GeoJSON FeatureCollection for a Point."""
    coordinates = [float(lon), float(lat)]
    if z is not None and str(z).strip() != "":
        coordinates.append(float(z))
        
    return {
        "type": "FeatureCollection",
        "features": [
            {
                "geometry": {
                    "type": "Point",
                    "coordinates": coordinates
                },
                "id": str(uuid.uuid4()),
                "properties": {
                    "nodeId": node_id
                },
                "type": "Feature"
            }
        ]
    }

def ensure_tile_hierarchy(resource_id, nodegroup_id):
    """
    Dynamically walks up the graph tree. If a parent nodegroup exists but lacks a tile,
    it generates the required parent tile first so Arches validation doesn't fail.
    """
    ng = NodeGroup.objects.get(pk=nodegroup_id)
    parent_tile_id = None
    
    # Check for a parent nodegroup
    if ng.parentnodegroup_id:
        parent_tile = ensure_tile_hierarchy(resource_id, ng.parentnodegroup_id)
        parent_tile_id = str(parent_tile.tileid)
        
    # Get or create the tile for THIS nodegroup
    tile = Tile.objects.filter(resourceinstance_id=resource_id, nodegroup_id=nodegroup_id).first()
    if not tile:
        tile = Tile.get_blank_tile_from_nodegroup_id(
            nodegroup_id, 
            resourceid=resource_id, 
            parenttile_id=parent_tile_id
        )
        tile.save() # Saves it immediately to establish the hierarchy
        
    return tile

def main():
    print("--- Starting Upload Script (Using Legacy ID Mapping) ---")
    
    # Dynamically find the exact Nodegroup the nodes belong to in the DB
    try:
        target_node = Node.objects.get(nodeid=POSITION_GEOJSON_NODE_ID)
        target_nodegroup_id = str(target_node.nodegroup_id)
    except Node.DoesNotExist:
        print("Error: Could not find GeoJSON Node in the database.")
        sys.exit(1)

    points_data = {}

    # 1. Read Local Coordinates CSV
    print(f"Reading Local CSV from {LOCAL_CSV_PATH}...")
    with open(LOCAL_CSV_PATH, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            csv_legacy_id = row['resource_id'].strip()
            points_data[csv_legacy_id] = {
                'local_x': row['x'],
                'local_y': row['y'],
                'local_z': row.get('z', '')
            }

    # 2. Read WGS84 Coordinates CSV
    print(f"Reading WGS84 CSV from {WGS84_CSV_PATH}...")
    with open(WGS84_CSV_PATH, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            csv_legacy_id = row['resource_id'].strip()
            if csv_legacy_id not in points_data:
                points_data[csv_legacy_id] = {}
            points_data[csv_legacy_id]['wgs_lon'] = row['wgs84_lon']
            points_data[csv_legacy_id]['wgs_lat'] = row['wgs84_lat']
            points_data[csv_legacy_id]['wgs_z'] = row.get('z', '')

    # 3. Process and Update Database
    print(f"\nBeginning upload for {len(points_data)} resources...")
    success_count = 0
    
    for csv_legacy_id, coords in points_data.items():
        try:
            # THIS IS THE KEY FIX: Look up the resource by legacyid!
            res = Resource.objects.filter(legacyid=csv_legacy_id).first()
            if not res:
                print(f"  [X] Skipped: No new resource found with legacy_id '{csv_legacy_id}'")
                continue

            real_resource_id = str(res.resourceinstanceid)

            # Safely fetch the exact nested tile using the real, new resource ID
            tile = ensure_tile_hierarchy(real_resource_id, target_nodegroup_id)
            updated = False

            if 'wgs_lon' in coords and 'wgs_lat' in coords:
                wgs_geojson = create_geojson_point(coords['wgs_lon'], coords['wgs_lat'], coords['wgs_z'], POSITION_GEOJSON_NODE_ID)
                tile.data[POSITION_GEOJSON_NODE_ID] = wgs_geojson
                updated = True
                
            if 'local_x' in coords and 'local_y' in coords:
                local_z = coords.get('local_z', '')
                local_text = f"{coords['local_x']} {coords['local_y']} {local_z}".strip()
                tile.data[MEASUREMENT_TXT_NODE_ID] = local_text
                updated = True
                
            if updated:
                tile.save() 
                print(f"  [✓] Successfully updated Resource (Legacy: {csv_legacy_id} -> Real: {real_resource_id})")
                success_count += 1
            
        except Exception as e:
            print(f"  [X] Failed to update Resource {csv_legacy_id}: {repr(e)}")

    print(f"\nFinished! Successfully updated {success_count} resources.")

if __name__ == "__main__":
    main()