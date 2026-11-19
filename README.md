# Arches for JU Excavations (Docker Deployment)

The official Docker configuration for deploying the [**Arches for JU Excavations application**](https://github.com/mn-lab-platform/arches-for-ju-excavations).

This deployment stack, together with the core application, was developed as part of the [**Mare Nostrum LAB Platform**](https://mn.cenagis.edu.pl) and is powered by the [**Arches Project**](https://www.archesproject.org).

Special thanks to the original creators of [**arches-via-docker**](https://github.com/opencontext/arches-via-docker) for the foundational Docker configurations used in this project.

## Setting Up Arches for JU Excavations
1. Clone this repository.
    ```bash
    git clone https://github.com/mn-lab-platform/arches-for-ju-excavations-project.git
    ```
2. Create an `.env` file in the root of the cloned codebase by copying [`edit_dot_env`](edit_dot_env):
    ``` bash
    cp edit_dot_env .env
    ```
3. Set the required environment variables in the `.env` file:
    - *`PUBLIC_PORT`*: The port on your machine that will be exposed to the internet and used for web access (e.g., 80).
    - *`DEPLOY_HOST`*: The main domain name where your Arches instance will be accessible (e.g., arches.example.com).
    - *`DOMAIN_NAMES`*: A space-separated list of all domains and IPs that should resolve to your Arches instance (e.g., arches.example.com localhost 127.0.0.1).
    - *`DJANGO_DEBUG`*: `True`/`true`/`False`/`false`. Setting this option to `True`/`true` is useful during development; for production environments, set it to `False`/`false`.
    - *`BUILD_PRODUCTION`*: Set to `False` for normal local development. When enabled, it tells the Docker build to compile the frontend in production mode for a production-ready bundle, which uses more memory and may fail on machines with less than ~8GB of RAM.
    - *`ADMIN_PASSWORD`*: Password for the superuser account described above.

4. Decide whether you want to back up the data stored in your Arches instance. This setup provides a service that handles backups automatically. Refer to [Backing Up and Restoring](#backing-up-and-restoring) before choosing one of the following commands:
    ```bash
    # Backup daemon WILL NOT start
    docker compose up --build -d
    ```
    or
     ```bash
    # Backup daemon WILL start
    docker compose --profile backup up --build -d
    ```
    The initial build may take several minutes.


5. Register all Arches for JU Excavations custom reports, plugins, and functions in your instance using [`register_extensions.sh`](arches_for_excavation_project/register_extensions.sh):
    ```bash
    docker exec -it arches ./register_extensions.sh
    ```

6. Grant access to the configured plugins and workflows for the Plugin Access group:
    ```bash
    docker exec -it arches python manage.py assign_plugin_permissions
    ```

7. Import all Arches for JU Excavations ontology and resource models into your instance:
    ```bash
    docker exec -it arches python manage.py packages -o load_package -a arches_for_excavation -y
    ```

8. (Optional) Configure the email backend for your Arches instance by updating the following variables in your `.env` file:
    - *`EMAIL_PASSWORD`*: Password for your email server. **If your password contains special characters (like '$'), wrap it in single quotes to avoid issues with Docker/Python parsing**.
    - *`DEFAULT_FROM_EMAIL`*: The display name and email address that will appear as the sender (e.g., `noreply@arches.example.com`).
    - *`EMAIL_USE_TLS`*: True/true/False/false
    - *`EMAIL_USE_SSL`*: True/true/False/false
    - *`EMAIL_HOST`*: The SMTP server address for sending emails (e.g., 'smtp.example.com').
    - *`EMAIL_HOST_USER`*: The username for authenticating with your SMTP server.
    - *`EMAIL_PORT`*: The port number for your SMTP server.
    
    After making these changes, restart the services so the application loads the updated configuration:
    ```bash
    docker compose restart
    ```
## Resource Instance Visibility

At the time this configuration was implemented, Arches versions before 8.2.0 used a *Default Allow* strategy for resource visibility. Under this strategy, resource instances are visible unless access is explicitly restricted.

This project supports Arches' *Default Deny* permission framework, which provides a more restrictive default: resource instances are hidden from regular users unless access is explicitly granted to specific users or groups.

### Granting a group access

The current configuration grants permissions to two groups:
- *`Resource Viewer` (group ID: 13)* — a custom group created for SSO configuration. It is granted the `view_resourceinstance` permission.
- *`Resource Editor` (group ID: 2)* — an Arches core group. It is granted the `change_resourceinstance` and `delete_resourceinstance` permissions.

These permissions are assigned for the resource graphs listed in `RESOURCE_GRAPH_IDS` in [`settings_local.py`](arches/settings_local.py):
```python
RESOURCE_GRAPH_IDS = {
    "annotation": "d1894fdd-41b3-44d3-aebb-ab44999f881e",
    "context": "2c536779-d3e6-43ef-bc0c-cd4d97dc8c6c",
    "coordinate_system": "855343ec-9d7c-4947-970c-e80b6cfacc4f",
    "digital_resource_3d": "039f5a45-82e2-4597-8609-d24c758bfd59",
    "digital_resource_iiif": "f1b9e37a-c3ba-4c26-a797-7f16302c031c",
    "special_find": "ac939663-80ce-43df-967d-42def45ef333",
    "trench": "cc91f1ff-6ea8-422c-be14-b818660f66f8",
}
```

The dictionary keys are descriptive slugs, and the values are resource graph IDs. Add or remove entries to customize which resource graphs are managed by this permission configuration.

Because [`settings_local.py`](arches/settings_local.py) is copied into the image during the Docker build, rebuild the `arches` container after changing it:

```bash
docker compose up --build -d arches
```

If necessary, restart Nginx separately so it serves the current frontend assets:

```bash
docker compose restart nginx
```

### Applying permission changes

After changing `RESOURCE_VIEWER_GROUP_ID`, `RESOURCE_GRAPH_IDS`, `PERMISSION_FRAMEWORK`, or `PERMISSION_DEFAULTS`, rebuild the Elasticsearch index:

```bash
docker exec -it arches python manage.py es reindex_database
```

## Backing Up and Restoring
Having a robust disaster recovery mechanism is one of the characteristics of good software. That is why this deployment environment comes with an integrated backup/restore service (hereafter **Backup Daemon**) based on [Restic](https://restic.net/) and Cron. It handles both PostGIS database records and media uploaded by users (the contents of `UPLOADED_FILES_FOLDER`).

To take advantage of the Backup Daemon you need to perform the following steps:
1. Define required additional variables inside your `.env` file:
    - *`BACKUPS_DIRECTORY`*: Path to the directory to which you'd like your backups to be saved (repository). Check out [available Restic repository setup options](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html). 
    - *`RESTIC_PASSWORD`*: A key required to access your backups repository. **Losing this password will render the repository inaccessible, so make sure to write it down in a secure and persistent location other than your `.env` file**.
2. Include the profile *backup* in your startup command:
    ```bash
    # Will start arches_backup_daemon container among other Arches For JU Excavations services
    docker compose --profile backup up --build -d
    ```
3. Initialize the Restic repository (**You only have to do this once for a specific *`BACKUPS_DIRECTORY`***):
    ```bash
    docker exec -it arches_backup_daemon restic init
    ```

And just like that, Backup Daemon is ready to back up and restore data from your Arches for JU Excavations instance. The backup script runs every day at 2:30 AM - feel free to change this schedule in [backup_daemon/crontab](backup_daemon\crontab) if needed. **Keep in mind that you need to reserve additional disk space for the backup data**. Thanks to the robustness of Restic, the required space is minimized - an additional disk volume roughly the size of your current data should be sufficient. To trigger a manual backup, run the [`backup.sh`](backup_daemon/backup.sh) script:
```bash
    docker exec -it arches_backup_daemon ./backup.sh
```

To rollback to a specific point in time, you must first access the SNAPSHOT_ID. Execute:
```bash
    docker exec -it arches_backup_daemon restic snapshots
```
It will return a table with all the information you need. Just copy the ID of the snapshot corresponding to the date you want to rollback your system to. In case the default view doesnt suit your needs - [Explore snapshot filtering and display options](https://restic.readthedocs.io/en/stable/045_working_with_repos.html).

Once you have your `SNAPSHOT_ID`, execute the [`restore.sh`](backup_daemon/restore.sh) script. It supports different recovery modes:
```bash
    # Usage: ./restore.sh [-y] <SNAPSHOT_ID> [all|db|media]
    docker exec -it arches_backup_daemon ./restore.sh <SNAPSHOT_ID>
```
Restore script modes:
- *`all`*: Restores both PostgreSQL database and all uploaded media files.
- *`db`*: Restores only the PostgreSQL database. Useful for quick rollbacks if only application data was corrupted.
- *`media`*: Restores only the uploaded files directory.


## Configuring an External OAuth Provider

For more information, refer to the [Arches external OAuth documentation](https://arches.readthedocs.io/en/stable/configuring/settings-beyond-the-ui/#using-single-sign-on-with-an-external-oauth-provider). To configure an external OAuth provider, such as Keycloak, edit the `.env` file and [`arches/settings_local.py`](arches/settings_local.py).

1. Enable external OAuth and set the client secret in `.env`:

    ```bash
    ENABLE_EXTERNAL_OAUTH=True
    EXTERNAL_OAUTH_SECRET=your-client-secret
    ```

    `EXTERNAL_OAUTH_SECRET` should contain the client secret issued by your identity provider. Do not commit the secret to the repository.

2. Replace the placeholders in `EXTERNAL_OAUTH_CONFIGURATION` in [`arches/settings_local.py`](arches/settings_local.py):

    ```python
    EXTERNAL_OAUTH_CONFIGURATION = {
        "default_user_groups": [<DEFAULT_USER_GROUPS>],
        "user_domains": [<USER_DOMAINS>],
        "uid_claim": "preferred_username",
        "app_id": <APP_ID>,
        "app_secret": get_optional_env_variable("EXTERNAL_OAUTH_SECRET"),
        "scopes": ["openid", "profile", "email"],
        "validate_id_token": True,
        "oidc_discovery_url": <OIDC_DISCOVERY_URL>,
    }
    ```

    Replace each placeholder with a value appropriate for your identity provider:

    - `<DEFAULT_USER_GROUPS>`: A comma-separated list of Arches group names to assign to newly created users.
    - `<USER_DOMAINS>`: A comma-separated list of permitted email domains, without the `@` symbol.
    - `<APP_ID>`: The OAuth client ID issued by your identity provider. Quote it if it is not a numeric value.
    - `<OIDC_DISCOVERY_URL>`: The OpenID Connect discovery URL published by your identity provider.

3. Rebuild the `arches` container so the updated settings are copied into the image:

    ```bash
    docker compose up --build -d arches
    ```

After restarting, users can sign in through the external OAuth provider.

## Customizing Your Arches for JU Excavations
1. Change the `.env` variables essential for this section:
    - *`APP_TITLE`*: The name displayed as page title as well as in the landing page header. Default: `Arches for JU Excavations`.
    - *`EXCAVATION_NAME`*: Name of the specific excavation site you are setting the Arches instance up for. It will be displayed as the title of the slides in the landing page. Default: `Arches for JU Excavations`.

2. Add your own logo and images for the landing-page slides in the [landing](arches_for_excavation_project/media/img/landing) media directory.
    - Place your logo in `custom/project_logo.png`.
    - Place your first slide image in `custom/landing_first.jpg`.
    - Place your second slide image in `custom/landing_second.jpg`.
    - Place your third slide image in `custom/landing_third.jpg`.

3. Customise the captions and attributions displayed in the landing-page slides by editing `LANDING_IMAGE_SLIDES_CONFIG` in [`arches/settings_local.py`](arches/settings_local.py). It must be a three-element list of dictionaries, where each dictionary contains a caption and an image attribution. Example:
    ```bash
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
    ```

4. Customise the email template content by editing `EXTRA_EMAIL_CONTEXT` in [`arches/settings_local.py`](arches/settings_local.py). It is a dictionary with the following keys:

    - *`salutation`*: The opening greeting string used in the email (e.g., "Hi").

    - *`expiration`*: A string defining how long the activation link remains valid (e.g., "24 hours").

    - *`arches_project_name`*: The title of your project instance.

    - *`greeting`*: The main body text of the email welcoming the user. Wrap this in Django's mark_safe() if you want to include custom HTML formatting or links.

    - *`button_text`*: The text displayed inside the main confirmation button (e.g., "Confirm").

    - *`domain_url`*: The domain variable (usually maps to _DOMAIN_URL) used to build the activation link.

    - *`footer_strong_text`*: Bolded text representing the institution or project name in the email footer. Wrap in mark_safe() to support HTML entities like &bull;.

    - *`footer_additional_text`*: Fine print, addresses, or contact details in the footer. Wrap in mark_safe() to support HTML entities like "&middot;".

    - *`email_header_image_url`*: Path to the icon that should be placed in the email header.
    - *`email_footer_image_url`*: Path to the icon that should be placed in the email footer.