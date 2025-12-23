😭😭😭 saved-searches.js:17  GET http://localhost:8004/search_component_data/saved-searches 500 (Internal Server Error):
- dodać w settings_local.py SAVED_SEARCHES = []
- walnąć w konsoli: docker exec -it arches python manage.py es reindex_database


😭😭😭sh: 1: eslint: not found
- docker exec -it arches npm install

😭😭😭Unable to save. NotFoundError(404, "{'_index': 'arches_slocal_concepts', '_id': 'ac41d9be-79db-4256-b368-2f4559cfbe55', 'found': False}")
- docker exec -it arches python manage.py es index_concepts