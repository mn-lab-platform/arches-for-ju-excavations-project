#!/usr/bin/env python3
import os
import sys
import json
import io
import django
from django.db import transaction
from django.utils import timezone

# Setup Django Environment
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "arches_for_excavation_project.settings")
sys.path.insert(0, "/arches_app/arches_for_excavation_project")
django.setup()

from arches.app.models.models import TileModel
import geopandas as gpd

GEOMETRY_NODE_ID = "17f97530-d293-11eb-b45b-020063fe0012"

ORIGINAL_WKT = """PROJCRS["PAP_2015",
    BASEGEOGCRS["ITRF_2008",
        DATUM["D_ITRF_2008",
            ELLIPSOID["GRS_1980",6378137.0,298.257222101,
                LENGTHUNIT["metre",1]]],
        PRIMEM["Greenwich",0,
            ANGLEUNIT["degree",0.0174532925199433]]],
    CONVERSION["Hotine Oblique Mercator (variant B)",
        METHOD["Hotine Oblique Mercator (variant B)", ID["EPSG",9815]],
        PARAMETER["Latitude of projection centre",34.759795222222202, ANGLEUNIT["degree",0.0174532925199433]],
        PARAMETER["Longitude of projection centre",32.407348347222197, ANGLEUNIT["degree",0.0174532925199433]],
        PARAMETER["Azimuth at projection centre",0.3895, ANGLEUNIT["degree",0.0174532925199433]],
        PARAMETER["Angle from Rectified to Skew Grid",0, ANGLEUNIT["degree",0.0174532925199433]],
        PARAMETER["Scale factor at projection centre",1, SCALEUNIT["unity",1]],
        PARAMETER["Easting at projection centre",1100.0, LENGTHUNIT["metre",1]],
        PARAMETER["Northing at projection centre",1100.0, LENGTHUNIT["metre",1]]],
    CS[Cartesian,2],
        AXIS["(E)",east,ORDER[1],LENGTHUNIT["metre",1]],
        AXIS["(N)",north,ORDER[2],LENGTHUNIT["metre",1]]]"""

TARGET_WKT = """PROJCRS["PAP2015-OPTIMIZED",
    BASEGEOGCRS["World Geodetic System 1984",
        DATUM["World Geodetic System 1984",
            ELLIPSOID["WGS 84",6378137,298.257223563,
                LENGTHUNIT["metre",1]],
            ID["EPSG",6326]],
        PRIMEM["Greenwich",0,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8901]]],
    CONVERSION["Hotine Oblique Mercator (variant B)",
        METHOD["Hotine Oblique Mercator (variant B)",
            ID["EPSG",9815]],
        PARAMETER["Latitude of projection centre",34.7597908419844,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8811]],
        PARAMETER["Longitude of projection centre",32.4073421460684,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8812]],
        PARAMETER["Azimuth at projection centre",0.395203358723502,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8813]],
        PARAMETER["Angle from Rectified to Skew Grid",0,
            ANGLEUNIT["degree",0.0174532925199433],
            ID["EPSG",8814]],
        PARAMETER["Scale factor at projection centre",1,
            SCALEUNIT["unity",1],
            ID["EPSG",8815]],
        PARAMETER["Easting at projection centre",1100.00078495866,
            LENGTHUNIT["metre",1],
            ID["EPSG",8816]],
        PARAMETER["Northing at projection centre",1100.00209280176,
            LENGTHUNIT["metre",1],
            ID["EPSG",8817]]],
    CS[Cartesian,2],
        AXIS["(E)",east,
            ORDER[1],
            LENGTHUNIT["metre",1,
                ID["EPSG",9001]]],
        AXIS["(N)",north,
            ORDER[2],
            LENGTHUNIT["metre",1,
                ID["EPSG",9001]]]]"""


def translate_geojson(geojson_dict):
    """Translates coordinates using Geopandas, generating a new GeoJSON, 
    but restores the exact original IDs and properties."""
    
    geojson_string = json.dumps(geojson_dict)
    gdf = gpd.read_file(io.StringIO(geojson_string))
    
    if gdf.empty:
        return geojson_dict
    
    if not gdf.crs:
        gdf.set_crs("EPSG:4326", inplace=True)
        
    gdf_local = gdf.to_crs(ORIGINAL_WKT)
    gdf_local.set_crs(TARGET_WKT, allow_override=True, inplace=True)
    gdf_fixed_4326 = gdf_local.to_crs("EPSG:4326")
    
    final_geojson_str = gdf_fixed_4326.to_json()
    translated_dict = json.loads(final_geojson_str)
    
    original_features = geojson_dict.get('features', [])
    translated_features = translated_dict.get('features', [])
    
    for i, new_feature in enumerate(translated_features):
        if i < len(original_features):
            if 'id' in original_features[i]:
                new_feature['id'] = original_features[i]['id']

            if 'properties' in original_features[i]:
                new_feature['properties'] = original_features[i]['properties']
            else:
                new_feature['properties'] = {}
                
    return translated_dict

def main():
    """Translates all geometry in the database from the original WKT to the target WKT."""
    tile_models = TileModel.objects.filter(data__has_key=GEOMETRY_NODE_ID)
    print(f"Found {tile_models.count()} TileModel instances to translate.")
    
    for tile_model in tile_models:
        original_geojson = tile_model.data.get(GEOMETRY_NODE_ID)

        if not original_geojson or 'features' not in original_geojson or len(original_geojson['features']) == 0:
            print(f"Skipping TileModel ID {tile_model.tileid} (No geometry features)")
            continue

        translated_geojson = translate_geojson(original_geojson)
        
        if translated_geojson != original_geojson:
            tile_model.data[GEOMETRY_NODE_ID] = translated_geojson
            tile_model.save()
            print(f"Translated geometry for TileModel ID {tile_model.tileid}")
        else:
            print(f"No translation needed for TileModel ID {tile_model.tileid}")

if __name__ == "__main__":
    main()