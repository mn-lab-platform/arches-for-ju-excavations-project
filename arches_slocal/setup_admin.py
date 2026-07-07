import os
import django

project_name = os.environ.get('ARCHES_PROJECT')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', f'{project_name}.settings')
django.setup()

from django.contrib.auth import get_user_model

User = get_user_model()
username = os.environ.get('ADMIN_USERNAME')
password = os.environ.get('ADMIN_PASSWORD')

if username and password:
    user, created = User.objects.get_or_create(username=username)
    
    user.set_password(password)
    user.is_superuser = True
    user.is_staff = True
    user.save()
    
    if created:
        print(f"Superuser '{username}' created successfully.")
    else:
        print(f"Superuser '{username}' password updated successfully.")
    
    if username != 'admin':
        try:
            default_admin = User.objects.get(username='admin')
            default_admin.delete()
            print("Security cleanup: Default 'admin' user found and deleted.")
        except User.DoesNotExist:
            pass
else:
    print("Skipping superuser creation: Missing ADMIN_USERNAME or ADMIN_PASSWORD.")