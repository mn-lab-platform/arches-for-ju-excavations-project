😭😭😭 saved-searches.js:17  GET http://localhost:8004/search_component_data/saved-searches 500 (Internal Server Error):
- dodać w settings_local.py SAVED_SEARCHES = []
- walnąć w konsoli: docker exec -it arches python manage.py es reindex_database