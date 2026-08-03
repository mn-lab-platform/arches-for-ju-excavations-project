import os
import django
from django.db.utils import OperationalError, ProgrammingError

project_name = os.environ.get('ARCHES_PROJECT')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', f'{project_name}.settings')
django.setup()

from django.contrib.auth import get_user_model

User = get_user_model()
password = os.environ.get('ADMIN_PASSWORD')

try:
    if password:
        user, created = User.objects.get_or_create(username='admin')
        
        user.set_password(password)
        user.is_superuser = True
        user.is_staff = True
        user.save()
        
        if created:
            print("Default 'admin' user created and password set.")
        else:
            print("Default 'admin' user found. Password synced with environment variable.")
            
    else:
        print("Skipping admin setup: Missing ADMIN_PASSWORD.")

except (OperationalError, ProgrammingError):
    print("Skipping admin setup: Database or tables not ready.")