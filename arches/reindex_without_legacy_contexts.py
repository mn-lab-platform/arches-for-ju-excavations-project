"""Rebuild arches-search SQL indexes, excluding restored resources with missing concepts.

Run inside the Arches container with::

    python manage.py shell < /tmp/reindex_without_legacy_contexts.py
"""

from arches.app.models.models import TileModel
from arches.app.models.system_settings import settings
from arches_search.indexing.index_from_tile import index_from_tile
from arches_search.indexing.indexing_factory import IndexingFactory
from arches_search.indexing.indexers.date import DateIndexing
from arches_search.indexing.indexers.geojson_feature_collection import (
    GeoJSONFeatureCollectionIndexing,
)
from arches_search.management.commands.arches_search import (
    Command,
    SEARCH_MODELS,
    _build_nodegroup_cache,
)
from django.db import connection
from django.contrib.gis.geos import GEOSGeometry
from arches_search.models.models import GeometrySearch
import json


# The installed arches-search date indexer accepts a space before the time,
# while restored date tiles contain ISO timestamps with a T separator.
_original_short_circuit_date = DateIndexing._short_circuit_date


def _short_circuit_iso_date(self, document, date_components, nodeid, node, tile):
    date_components[2] = date_components[2].split("T", 1)[0]
    return _original_short_circuit_date(
        self, document, date_components, nodeid, node, tile
    )


DateIndexing._short_circuit_date = _short_circuit_iso_date


def _coordinates_2d(coordinates):
    if coordinates and isinstance(coordinates[0], (int, float)):
        return coordinates[:2]
    return [_coordinates_2d(part) for part in coordinates]


def _index_geometry_2d(self, tile, node):
    feature_collection = tile.data.get(str(node.nodeid))
    if not feature_collection:
        return []
    results = []
    for feature in feature_collection.get("features", []):
        geometry = feature.get("geometry")
        if not geometry:
            continue
        geometry = dict(geometry)
        if "coordinates" in geometry:
            geometry["coordinates"] = _coordinates_2d(geometry["coordinates"])
        try:
            geom = GEOSGeometry(json.dumps(geometry), srid=4326)
        except Exception:
            continue
        results.append(
            GeometrySearch(
                node_alias=node.alias,
                tileid_id=tile.tileid,
                resourceinstanceid_id=tile.resourceinstance_id,
                datatype=self.datatype.datatype_name,
                graph_slug=node.graph.slug,
                geom=geom,
            )
        )
    return results


GeoJSONFeatureCollectionIndexing.index = _index_geometry_2d


with connection.cursor() as cursor:
    cursor.execute(
        """
        SELECT DISTINCT t.resourceinstanceid
        FROM tiles t
        CROSS JOIN LATERAL jsonb_each(t.tiledata) e
        JOIN nodes n ON n.nodeid::text = e.key
            AND n.datatype IN ('concept', 'concept-list')
        CROSS JOIN LATERAL jsonb_array_elements_text(
            CASE WHEN jsonb_typeof(e.value) = 'array'
                 THEN e.value ELSE jsonb_build_array(e.value) END
        ) v(valueid)
        LEFT JOIN values vl ON vl.valueid::text = v.valueid
        WHERE e.value <> 'null'::jsonb AND vl.valueid IS NULL
        """
    )
    excluded_ids = [row[0] for row in cursor.fetchall()]

if not excluded_ids:
    raise RuntimeError("No resources with missing concept values found; check restore state")

qs = TileModel.objects.exclude(
    resourceinstance_id=settings.SYSTEM_SETTINGS_RESOURCE_ID
).exclude(resourceinstance_id__in=excluded_ids)
total = qs.count()
print(f"Excluding {len(excluded_ids)} legacy resources; indexing {total} tiles", flush=True)

command = Command()
command.delete_indexes()
batch_size = settings.INDEX_BATCH_SIZE
nodegroup_cache = _build_nodegroup_cache()
indexing_factory = IndexingFactory()
values_to_index = {model: [] for model in SEARCH_MODELS}

for count, tile in enumerate(qs.iterator(chunk_size=batch_size), start=1):
    try:
        indexed_values = index_from_tile(
            tile,
            delete_existing=False,
            indexing_factory=indexing_factory,
            nodegroup_cache=nodegroup_cache,
        ) or []
    except Exception as exc:
        raise RuntimeError(
            f"Cannot index tile {tile.tileid}, resource {tile.resourceinstance_id}"
        ) from exc
    for value in indexed_values:
        values_to_index[type(value)].append(value)
    if count % batch_size == 0:
        command._flush(values_to_index, batch_size)
        print(f"Indexed {count}/{total} tiles", flush=True)

command._flush(values_to_index, batch_size)
print(f"Finished indexing {total} tiles", flush=True)
