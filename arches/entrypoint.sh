#!/bin/bash

# APP and YARN folder locations
APP_FOLDER=${APP_ROOT}
APP_COMP_FOLDER=${APP_COMP_FOLDER}
GUNICORN_CONFIG_PATH=${APP_COMP_FOLDER}/gunicorn_config.py
STATIC_ROOT=/static_root
STATIC_JS=${STATIC_ROOT}/js
WEBPACK_STATS_PATH=${APP_FOLDER}/webpack-stats.json 

# Environmental Variables
export DJANGO_PORT=${DJANGO_PORT:-8000}
COUCHDB_URL=${COUCHDB_URL}
#Utility functions that check db status
wait_for_db() {
	echo "Testing if database server is up..."
	while [[ ! ${return_code} == 0 ]]
	do
        psql --host=${PGHOST} --port=${PGPORT} --user=${PGUSERNAME} --dbname=postgres -c "select 1" >&/dev/null
		return_code=$?
		sleep 1
	done
	echo "Database server is up"

    echo "Testing if Elasticsearch is up..."
    while [[ ! ${return_code} == 0 ]]
    do
        curl -s "http://${ESHOST}:${ESPORT}/_cluster/health?wait_for_status=green&timeout=60s" >&/dev/null
        return_code=$?
        sleep 1
    done
    echo "Elasticsearch is up"
}

db_exists() {
	echo "Checking if database "${PGDBNAME}" exists..."
	count=`psql --host=${PGHOST} --port=${PGPORT} --user=${PGUSERNAME} --dbname=postgres -Atc "SELECT COUNT(*) FROM pg_catalog.pg_database WHERE datname='${PGDBNAME}'"`

	# Check if returned value is a number and not some error message
	re='^[0-9]+$'
	if ! [[ ${count} =~ $re ]] ; then
	   echo "Error: Something went wrong when checking if database "${PGDBNAME}" exists..." >&2;
	   echo "Exiting..."
	   exit 1
	fi

	# Return 0 (= true) if database exists
	if [[ ${count} > 0 ]]; then
		return 0
	else
		return 1
	fi
}

#### Install
init_arches() {
	echo "Checking if Arches project "${ARCHES_PROJECT}" exists..."
	if [[ ! -d ${APP_FOLDER} ]] || [[ ! "$(ls ${APP_FOLDER})" ]]; then
		echo ""
		echo "----- Custom Arches project '${ARCHES_PROJECT}' does not exist. -----"
		echo "----- Creating '${ARCHES_PROJECT}'... -----"
		echo ""

		cd ${APP_FOLDER}
		echo "Sleep for a 45 seconds because elastic search seems to need the wait (a total hack)..."
		sleep 45s;
		arches-project create ${ARCHES_PROJECT}
		run_setup_db
		setup_couchdb

		exit_code=$?
		if [[ ${exit_code} != 0 ]]; then
			echo "Something went wrong when creating your Arches project: ${ARCHES_PROJECT}."
			echo "Exiting..."
			exit ${exit_code}
		fi
	else
		echo "Custom Arches project '${ARCHES_PROJECT}' exists."
		wait_for_db
		if db_exists; then
			echo "Database ${PGDBNAME} already exists."
			echo "Skipping Package Loading"
		else
			echo "Database ${PGDBNAME} does not exists yet."
			run_setup_db
			run_elastic_safe_migrations
			setup_couchdb
		fi
	fi
}

# Setup Couchdb
setup_couchdb() {
    echo "--- SKIP Creating couchdb system databases (not in V7, no Collector) ---"
	# echo "Sleep for a 10 seconds because elastic search seems to need the wait (a total hack)..."
	# sleep 10s;
    # curl -X PUT ${COUCHDB_URL}/_users
    # curl -X PUT ${COUCHDB_URL}/_global_changes
    # curl -X PUT ${COUCHDB_URL}/_replicator
}


#### Misc
check_settings_local() {
	# Make sure we have a settings_local in the proper location of the project
	cd ${APP_COMP_FOLDER}
	echo "The directory ${APP_COMP_FOLDER} contains:"
	ls -l
	echo "---------------------------------------------------------------"
}

#### Run commands
start_celery_supervisor() {
	echo ""
	echo "----- START CELERY SUPERVISOR -----"
	echo ""
	echo "Sleep 30s in the hope that arches_redis will be fully up and running..."
	sleep 30s;
	if [ -f "/tmp/supervisor.sock" ]; then
		echo "The celery supervisor seems started, so why try to start it again? "
	else
		echo "The celery supervisor has yet to start, so we'll start it.."
		cd ${APP_FOLDER}
		wait-for-it arches_redis:6379 -t 120 && supervisord -c arches_for_excavation-supervisor.conf
	fi
}

run_createcachetable() {
	echo ""
	echo "----- RUNNING CREATE CACHETABLE -----"
	echo ""
	cd ${APP_FOLDER}
	python3 manage.py createcachetable
}

run_elastic_safe_migrations() {
	echo ""
	echo "----- RUNNING DATABASE MIGRATIONS WITH ELASTIC CHECK -----"
	echo ""
	echo "Testing if Elasticsearch is up..."
    while [[ ! ${return_code} == 0 ]]
    do
        curl -s "http://${ESHOST}:${ESPORT}/_cluster/health?wait_for_status=green&timeout=60s" >&/dev/null
        return_code=$?
        sleep 1
    done
    echo "Elasticsearch is up"
	cd ${APP_FOLDER}
	echo "Sleep for a 20 seconds because elastic search seems to need the wait (a total hack)..."
	echo "We're running migrations in case the initial db setup failed because elasticsearch was still not quite ready"
	sleep 20s;
	echo "Now do Migrations..."
	python3 manage.py migrate
}

run_make_migrations() {
	echo ""
	echo "----- RUNNING DATABASE MAKE MIGRATIONS -----"
	echo ""
	cd ${APP_FOLDER}
	python manage.py makemigrations
}

run_migrations() {
	echo ""
	echo "----- RUNNING DATABASE MIGRATIONS -----"
	echo ""
	cd ${APP_FOLDER}
	python manage.py migrate
}

run_es_reindex() {
	echo ""
	echo "----- RUNNING ELASTIC SEARCH (ES) REINDEX DATABASE -----"
	echo ""
	cd ${APP_FOLDER}
	python3 manage.py es reindex_database
}


run_collect_static() {
	echo ""
	echo "----- RUNNING COLLECT STATIC -----"
	echo ""
	if [[ ${BUILD_PRODUCTION} == 'True' ]]; then
		echo "Skipping collectstatic, hopefully buildproduction will do the trick..."
	else
		cd ${APP_FOLDER}
		python3 manage.py collectstatic --noinput
	fi
	echo "---------------------------------------------------------------"
}

run_collect_static_nocheck() {
	echo ""
	echo "----- RUNNING COLLECT STATIC -----"
	echo ""
	cd ${APP_FOLDER}
	python3 manage.py collectstatic --noinput
	echo "---------------------------------------------------------------"
}

run_setup_arches_setup_webpack() {
    if [[ ! -f ${WEBPACK_STATS_PATH} ]] || [[ ! -d ${STATIC_JS} ]] || [[ ! "$(ls ${STATIC_JS})" ]]; then
        cd ${APP_FOLDER}
        echo "Starting Django development server" 
        python manage.py runserver 0.0.0.0:8000 &
        
        if [[ ${BUILD_PRODUCTION} == 'True' ]]; then
            echo "Running npm PRODUCTION build and collectstatic" 
            npm run build_production && python manage.py collectstatic --noinput
        else
            echo "Running npm DEVELOPMENT build and collectstatic" 
            npm run build_development && python manage.py collectstatic --noinput
        fi
    else
        echo "Webpack and Collectstatic for setup already completed.";
    fi

    RUNSERVER_PID=$(pgrep -f "manage.py runserver") 
    if [ -n "$RUNSERVER_PID" ]; then 
        echo "Killing manage.py runserver process with PID $RUNSERVER_PID" 
        kill -9 $RUNSERVER_PID
        echo "Process $RUNSERVER_PID killed" 
    else 
        echo "No manage.py runserver process found"
    fi
}

run_list_static() {
	echo ""
	echo "----- VIEW COLLECTED STATIC -----"
	echo ""
	cd /static_root
	ls
	echo "---------------------------------------------------------------"
}

run_setup_db() {
	echo ""
	echo "----- RUNNING SETUP_DB -----"
	echo ""
	echo "Testing if Elasticsearch is up..."
    while [[ ! ${return_code} == 0 ]]
    do
        curl -s "http://${ESHOST}:${ESPORT}/_cluster/health?wait_for_status=green&timeout=60s" >&/dev/null
        return_code=$?
        sleep 1
    done
    echo "Elasticsearch is up, pause for 10 secs to be sure."
	sleep 10s;
	echo "Now we should be safe to setup the database"
	cd ${APP_FOLDER}
	python3 manage.py setup_db --force
}

run_load_package() {
	echo ""
	echo "----- *** LOADING PACKAGE: ${ARCHES_PROJECT} *** -----"
	echo ""
	cd ${APP_FOLDER}
	python3 manage.py packages -o load_package -s ${ARCHES_PROJECT}/pkg -db -dev -y
}

run_django_server() {
	echo ""
	echo "----- *** RUNNING DJANGO SERVER *** -----"
	echo ""
	sleep 5
	cd ${APP_FOLDER}
	if [[ ${DJANGO_DEBUG} == 'True' ]]; then
		echo "Running DEBUG mode Django"
		exec sh -c "python manage.py runserver 0.0.0.0:${DJANGO_PORT}"
	else
		echo "Should run the production mode Arches Django via gunicorn via:"
		# The GUNICORN_CONFIG_PATH breaks this, (errors in urls.py) so we'll just run it directly
		# echo "gunicorn ${ARCHES_PROJECT}.wsgi:application --config ${GUNICORN_CONFIG_PATH}"
		# exec sh -c "gunicorn ${ARCHES_PROJECT}.wsgi:application --config ${GUNICORN_CONFIG_PATH}"
		echo "gunicorn -w 12 -b 0.0.0.0:${DJANGO_PORT} ${ARCHES_PROJECT}.wsgi:application --timeout 3600"
		exec sh -c "gunicorn -w 12 -b 0.0.0.0:${DJANGO_PORT} ${ARCHES_PROJECT}.wsgi:application --timeout 3600"
		# echo "gunicorn -b 0.0.0.0:${DJANGO_PORT} ${ARCHES_PROJECT}.wsgi:application"
		# exec sh -c "gunicorn -b 0.0.0.0:${DJANGO_PORT} ${ARCHES_PROJECT}.wsgi:application"
	fi
}

run_setup_admin_password() {
    echo ""
    echo "----- RUNNING SETUP ADMIN PASSWORD-----"
    echo ""
    cd ${APP_FOLDER}
    echo "Setting up superuser from environment variables..."
    python3 setup_admin_password.py
    echo "---------------------------------------------------------------"
}

run_setup_mn_thesaurus_provider() {
    echo ""
    echo "----- RUNNING SETUP MN THERAUS PROVIDER -----"
    echo ""
    cd ${APP_FOLDER}
    echo "Registering MN Thesaurus SPARQL Provider..."
    python3 manage.py setup_mn_thesaurus_provider
    echo "---------------------------------------------------------------"
}

run_create_custom_auth_groups() {
	echo ""
	echo "----- RUNNING CREATE CUSTOM AUTH GROUPS -----"
	echo ""
	cd ${APP_FOLDER}
	echo "Creating custom authentication groups..."
	python3 manage.py create_custom_auth_groups
	echo "---------------------------------------------------------------"
}

#### Main commands
run_arches() {
	init_arches
	run_elastic_safe_migrations
	run_createcachetable
	start_celery_supervisor
	run_setup_arches_setup_webpack
	run_setup_admin_password
	run_create_custom_auth_groups
	run_setup_mn_thesaurus_provider
	run_django_server
}

#### Main commands
run_livereload() {
	run_livereload_server
}

### Starting point ###

# trying not to use virtualenv???
# activate_virtualenv

# Use -gt 1 to consume two arguments per pass in the loop
# (e.g. each argument has a corresponding value to go with it).
# Use -gt 0 to consume one or more arguments per pass in the loop
# (e.g. some arguments don't have a corresponding value to go with it, such as --help ).

# If no arguments are supplied, assume the server needs to be run
if [[ $#  -eq 0 ]]; then
	wait_for_db
	run_arches
fi

# Else, process arguments
echo "Full command: $@"
while [[ $# -gt 0 ]]
do
	key="$1"
	echo "Command: ${key}"

	case ${key} in
		run_arches)
			wait_for_db
			run_arches
		;;
		run_livereload)
			run_livereload_server
		;;
		run_collect_static)
			run_collect_static
		;;
		run_collect_static_nocheck)
			run_collect_static_nocheck
		;;
		run_list_static)
			run_list_static
		;;
		run_setup_arches_setup_webpack)
			run_setup_arches_setup_webpack
		;;
		run_setup_admin_password)
            wait_for_db
            run_setup_admin_password
        ;;
		run_create_custom_auth_groups)
			wait_for_db
			run_create_custom_auth_groups
		;;
		run_setup_mn_thesaurus_provider)
			wait_for_db
			run_setup_mn_thesaurus_provider
		;;
		setup_arches)
			start_celery_supervisor
			wait_for_db
			setup_arches
		;;
		run_make_migrations)
			wait_for_db
			run_make_migrations
		;;
		run_migrations)
			wait_for_db
			run_migrations
		;;
		run_es_reindex)
			wait_for_db
			run_es_reindex
		;;
		help|-h)
			display_help
		;;
		*)
            cd ${APP_FOLDER}
			"$@"
			exit 0
		;;
	esac
	shift # next argument or value
done
