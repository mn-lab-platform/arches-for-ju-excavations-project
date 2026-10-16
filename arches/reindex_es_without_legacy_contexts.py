"""Rebuild Arches Elasticsearch indexes without resources with missing concepts.

Run inside the Arches container with::

    python manage.py shell < /tmp/reindex_es_without_legacy_contexts.py
"""

from arches.app.models import models
from arches.app.models.resource import Resource
from arches.app.models.system_settings import settings
from arches.app.search.mappings import RESOURCES_INDEX
from arches.app.search.search_engine_factory import SearchEngineInstance as se
from arches.app.utils import index_database
from arches.management.commands.es import Command
from django.db import connection


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

resource_types = list(
    models.GraphModel.objects.filter(isresource=True)
    .exclude(graphid=settings.SYSTEM_SETTINGS_RESOURCE_MODEL_ID)
    .exclude(publication=None)
    .values_list("graphid", flat=True)
)
resources = Resource.objects.filter(graph_id__in=resource_types).exclude(
    resourceinstanceid__in=excluded_ids
)
total = resources.count()
print(f"Excluding {len(excluded_ids)} legacy resources; indexing {total} resources", flush=True)

command = Command()
command.delete_indexes()
command.setup_indexes()
index_database.index_concepts(clear_index=False)
index_database.index_resources_using_singleprocessing(
    resources=resources,
    batch_size=500,
    quiet=False,
    title="Resources without broken concepts",
)
index_database.index_custom_indexes(clear_index=False)
indexed = se.count(index=RESOURCES_INDEX)
print(f"Finished Elasticsearch indexing: {indexed} resources", flush=True)
