😭😭😭 saved-searches.js:17  GET http://localhost:8004/search_component_data/saved-searches 500 (Internal Server Error):
- dodać w settings_local.py SAVED_SEARCHES = []
- walnąć w konsoli: docker exec -it arches python manage.py es reindex_database


😭😭😭sh: 1: eslint: not found
- docker exec -it arches npm install

😭😭😭Unable to save. NotFoundError(404, "{'_index': 'arches_for_excavation_concepts', '_id': 'ac41d9be-79db-4256-b368-2f4559cfbe55', 'found': False}")
- docker exec -it arches python manage.py es index_concepts

😭😭😭Podczas npm run build_development
[webpack-cli] Error: EACCES: permission denied, unlink '/arches_app/arches_for_excavation/arches_for_excavation/media/build/cesium/Assets/Textures/maki/hospital.png'
- wywołać jeszcze raz run build_development 🤯