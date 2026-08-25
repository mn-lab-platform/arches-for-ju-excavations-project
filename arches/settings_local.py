import os
from django.core.exceptions import ImproperlyConfigured
import ast
import arches_for_excavation
from .settings import INSTALLED_APPS, TEMPLATES, STATICFILES_DIRS
from django.utils.safestring import mark_safe

def get_env_variable(var_name):
    msg = "Set the %s environment variable"
    try:
        return os.environ[var_name]
    except KeyError:
        error_msg = msg % var_name
        raise ImproperlyConfigured(error_msg)

def get_optional_env_variable(var_name):
    try:
        return os.environ[var_name]
    except KeyError:
        return None
from .settings import (
    APP_ROOT,
    INSTALLED_APPS,
    STATICFILES_DIRS,
    TEMPLATES,
    UPLOADED_FILES_DIR,
)

RASTER_DATA_DIR = os.path.join(
    APP_ROOT,
    UPLOADED_FILES_DIR,
    "iiif_raster",
)

TITILER_DATA_MOUNT = "/data"

IIIF_GEOTIFF_META_DIR = os.path.join(
    APP_ROOT,
    UPLOADED_FILES_DIR,
    "iiif_geotiff_meta",
)

IIIF_RAW_DEM_DIR = os.path.join(
    APP_ROOT,
    UPLOADED_FILES_DIR,
    "iiif_raw_dem",
)
MODE = get_env_variable("DJANGO_MODE")
DEBUG = ast.literal_eval(get_env_variable("DJANGO_DEBUG"))
DEPLOY_HOST = get_env_variable("DEPLOY_HOST")
DOMAIN_NAMES = get_env_variable("DOMAIN_NAMES").split()
is_localhost = any(host in ['localhost', '127.0.0.1', '0.0.0.0'] for host in DOMAIN_NAMES)
APP_NAME = get_env_variable("ARCHES_PROJECT")
TIME_ZONE = get_optional_env_variable("TZ") or "Europe/Warsaw"
if not DEBUG:
    SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
    if not is_localhost:
        SESSION_COOKIE_SECURE = True
        CSRF_COOKIE_SECURE = True
    
    CSRF_TRUSTED_ORIGINS = [
        f"https://{DEPLOY_HOST}",
        "http://localhost:8000",
        "http://127.0.0.1:8000",
        "http://localhost",
        "http://127.0.0.1",
    ]

APP_DIR = os.path.dirname(arches_for_excavation.__file__)
WRAPPER_MEDIA_DIR = os.path.join(os.path.dirname(__file__), 'media')

TEMPLATES[0]['DIRS'] = [os.path.join(APP_DIR, 'templates')] + list(TEMPLATES[0]['DIRS'])
STATICFILES_DIRS = [WRAPPER_MEDIA_DIR, os.path.join(APP_DIR, 'media')] + list(STATICFILES_DIRS)

if 'arches_for_excavation' not in INSTALLED_APPS:
    INSTALLED_APPS += ('arches_for_excavation',)

CUSTOM_PROCESSOR = 'arches_for_excavation.context_processors.custom_context'
if CUSTOM_PROCESSOR not in TEMPLATES[0]['OPTIONS']['context_processors']:
    TEMPLATES[0]['OPTIONS']['context_processors'].append(CUSTOM_PROCESSOR)

DATABASES = {
    "default": {
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "NAME": get_env_variable("PGDBNAME"),
        "USER": get_env_variable("PGUSERNAME"),
        "PASSWORD": get_env_variable("PGPASSWORD"),
        "HOST": get_env_variable("PGHOST"),
        "PORT": get_env_variable("PGPORT"),
        "POSTGIS_TEMPLATE": "template_postgis",
    }
}

ARCHES_NAMESPACE_FOR_DATA_EXPORT = get_optional_env_variable("ARCHES_EXPORT_NAMESPACE") or get_env_variable("ARCHES_NAMESPACE")

CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": "redis://arches_redis:6379/1",
    },
    "user_permission": {
        "BACKEND": "django.core.cache.backends.db.DatabaseCache",
        "LOCATION": "user_permission_cache",
    },
}

CELERY_BROKER_URL = "redis://@arches_redis:6379/0"

ELASTICSEARCH_HTTP_PORT = get_env_variable("ESPORT")
ELASTICSEARCH_HOSTS = [
    {
        "scheme": "http", 
        "host": get_env_variable("ESHOST"), 
        "port": int(ELASTICSEARCH_HTTP_PORT),
    }
]

USER_ELASTICSEARCH_PREFIX = get_optional_env_variable("ELASTICSEARCH_PREFIX")
if USER_ELASTICSEARCH_PREFIX:
    ELASTICSEARCH_PREFIX = USER_ELASTICSEARCH_PREFIX

ALLOWED_HOSTS = DOMAIN_NAMES

USER_SECRET_KEY = get_optional_env_variable("DJANGO_SECRET_KEY")
if USER_SECRET_KEY:
    SECRET_KEY = USER_SECRET_KEY

STATIC_ROOT = "/static_root"

LANGUAGE_CODE = 'en'
LANGUAGES = [
    ('en', ('English')),
    ('ar', ('Arabic')),
    ('he', ('Hebrew')),
]
SHOW_LANGUAGE_SWITCH = False

APP_TITLE = get_optional_env_variable("APP_TITLE") or "Arches for JU Excavation"
_DOMAIN_URL = f"https://{DEPLOY_HOST}"

DEFAULT_FROM_EMAIL = get_optional_env_variable("DEFAULT_FROM_EMAIL") or "xxxx@xxx.com"
EMAIL_USE_TLS = get_optional_env_variable("EMAIL_USE_TLS") or "false"
EMAIL_USE_TLS = EMAIL_USE_TLS.lower() in ['true', '1', 't']
EMAIL_USE_SSL = get_optional_env_variable("EMAIL_USE_SSL") or "false"
EMAIL_USE_SSL = EMAIL_USE_SSL.lower() in ['true', '1', 't']
EMAIL_HOST = get_optional_env_variable("EMAIL_HOST") or 'smtp.gmail.com'
EMAIL_HOST_USER = get_optional_env_variable("EMAIL_HOST_USER") or "xxxx@xxx.com"
EMAIL_HOST_PASSWORD = get_optional_env_variable("EMAIL_PASSWORD") or "xxxx"
EMAIL_PORT = int(get_optional_env_variable("EMAIL_PORT") or "587")

EXTRA_EMAIL_CONTEXT = {
    "salutation": "Hi", 
    "expiration": '24 hours', 
    "arches_project_name": APP_TITLE,
    "greeting": mark_safe("""
        Thanks for signing up to the <strong><a href="https://www.archesproject.org/" style="color:#0070d2; text-decoration:underline;">Arches</a></strong> instance created as part of the 
        <strong><a href="https://mare.id.uj.edu.pl/pl" style="color:#0070d2; text-decoration:underline;">Mare Nostrum Lab</a></strong>, a project of the 
        <strong>Institute of Archaeology at Jagiellonian University</strong>. 
        All you need to do is confirm your email address by clicking the button below and we are good to go. 🏛️
    """),
    "button_text": "Confirm",
    "domain_url": _DOMAIN_URL,
    "footer_strong_text": mark_safe("Institute of Archaeology &bull; Jagiellonian University"),
    "footer_additional_text": mark_safe("Gołębia 11 &middot; 31-007 Kraków &middot; Poland")
}

LANDING_IMAGE_SLIDES_CONFIG = [
    {
        "caption": "Arches for JU Excavations - To edit this caption, image and attribution, please check the manual.",
        "image_attribution": "Collegium Novum. Photo by Swifteye"
    },
    {
        "caption": "Arches for JU Excavations - To edit this caption, image and attribution, please check the manual.",
        "image_attribution": "Assembly Hall, Collegium Novum. Photo by Anna Wojnar"
    },
    {
        "caption": "Arches for JU Excavations - To edit this caption, image and attribution, please check the manual.",
        "image_attribution": "Main Square, Kraków. Photo by Swifteye"
    }
]