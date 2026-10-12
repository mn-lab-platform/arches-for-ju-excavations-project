# Arches for JU Excavations (Docker Deployment)

The official Docker configuration for deploying the [**Arches for JU Excavations Application**](https://github.com/mn-lab-platform/arches-for-ju-excavations). 

This deployment stack, alongside the core application, was developed as part of the [**Mare Nostrum LAB Platform**](https://mn.cenagis.edu.pl) and is powered by the [**Arches Project**](https://www.archesproject.org). 

Special thanks to the original creators of [**arches-via-docker**](https://github.com/opencontext/arches-via-docker) for the foundational Docker configurations used in this project.

## Setting Up Arches for JU Excavations on Your Machine
1. Clone this repository.
    ```bash
    git clone https://github.com/mn-lab-platform/arches-for-ju-excavations-project.git
    ```
2. Create an .env file in the root of the cloned codebase, by copying the `edit_dot_env` file: 
    ``` bash
    cp edit_dot_env .env
    ```
3. Change essential env variables in the `.env` file:
    - *`PUBLIC_PORT`*: The port on your machine that will be exposed to the internet and used for web access (e.g., 80).
    - *`DEPLOY_HOST`*: The main domain name where your Arches instance will be accessible (e.g., arches.example.com).
    - *`DOMAIN_NAMES`*: A space-separated list of all domains and IPs that should resolve to your Arches instance (e.g., arches.example.com localhost 127.0.0.1).
    - *`DJANGO_DEBUG`*: True/true/False/false. Setting this option to True/true is useful during development, however for production-ready environments, it must strictly be set to False/false.
    - *`BUILD_PRODUCTION`*: Set to `False` for normal local development. When enabled, it tells the Docker build to compile the frontend in production mode for a production-ready bundle, which uses more memory and may fail on machines with less than ~8GB of RAM.
    - *`ADMIN_PASSWORD`*: Password for the superuser account described above.

4.  At this point you should decide whether you'd like to backup the data stored in your Arches instance. This setup provides a service that handles that automatically for you. Please refer to the [Backing Up and Restoring](#backing-up-and-restoring) section of this document before diving into the commands below. Once you make the decision you are ready to start your Arches Project instance. Depending on your choice run one of the commands:  
    ```bash
    # Backup daemon WILL NOT start
    docker compose up --build -d
    ```
    or
     ```bash
    # Backup daemon WILL start
    docker compose --profile backup up --build -d
    ```
    Feel free to go grab yourself a coffee, it might take a while :).


5. Register all Arches for JU Excavations custom reports, plugins and functions in your instance:
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

8. (Optional) Set up mailing backend for your arches instance, to do so overwrite variables listed below inside your `.env` file:
    - *`EMAIL_PASSWORD`*: Password for your email server. **If your password contains special characters (like '$'), wrap it in single quotes to avoid issues with Docker/Python parsing**.
    - *`DEFAULT_FROM_EMAIL`*: The display name and email address that will appear as the sender (e.g., <noreply@arches.example.com>').
    - *`EMAIL_USE_TLS`*: True/true/False/false
    - *`EMAIL_USE_SSL`*: True/true/False/false
    - *`EMAIL_HOST`*: The SMTP server address for sending emails (e.g., 'smtp.example.com').
    - *`EMAIL_HOST_USER`*: The username for authenticating with your SMTP server.
    - *`EMAIL_PORT`*: The port number for your SMTP server.
    
    After doing so, remember to restart your services in order for the system to acknowledge the changes:
    ```bash
    docker compose restart
    ```

## Backing Up and Restoring
Having a robust disaster recovery mechanism is one of the characteristics of good software. That is why this deployment environment comes with an integrated backup/restore service (hereafter **Backup Daemon**) based on [Restic](https://restic.net/) + Cron stack. It handles both PostGIS database records and media uploaded by the users (i.e. the content of *`UPLOADED_FILES_FOLDER`*).

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

And just like that Backup Daemon is ready to backup and restore data from your Arches for JU Excavations instance. To backup your data simply execute:
```bash
    docker exec -it arches_backup_daemon ./backup.sh
```
Similarly to rollback to a specific point in time execute:
```bash
    docker exec -it arches_backup_daemon ./restore.sh <SNAPSHOT_ID>
```

To access the SNAPSHOT_ID necessary for the restore command to run, execute:
```bash
    docker exec -it arches_backup_daemon restic snapshots
```
It will return a table with all the information you need. Just copy the ID of the snapshot corresponding to the date you want to rollback your system to. In case the default view doesnt suit your needs - [Explore snapshot filtering and display options](https://restic.readthedocs.io/en/stable/045_working_with_repos.html).


## Customizing Your Arches for JU Excavations
1. Change the `.env` variables essential for this section:
    - *`APP_TITLE`*: The name displayed as page title as well as in the landing page header. Default: `Arches for JU Excavations`.
    - *`EXCAVATION_NAME`*: Name of the specific excavation site you are setting the Arches instance up for. It will be displayed as the title of the slides in the landing page. Default: `Arches for JU Excavations`.

2. Add your own logo and images for the slides in the landing page. Go to `<DIR_YOU_CLONED_THIS_REPO_INTO>/arches_for_excavation_project/media/img/landing`.
    - Place your logo in `./custom/project_logo.png`.
    - Place your first slide image in `./custom/landing_first.jpg`.
    - Place your second slide image in `./custom/landing_second.jpg`.
    - Place your third slide image in `./custom/landing_third.jpg`.

3. Customise the captions and attributions displayed in the landing page slides. Go to `<DIR_YOU_CLONED_THIS_REPO_INTO>/arches/settings_local.py` and edit/add a variable `LANDING_IMAGE_SLIDES_CONFIG`. It is expected to be a 3 element list of dictionaries, where each dictionary contains 2 key-value pairs. The first one is a caption to be displayed in the text box of a slide in the landing page, and the other is the attribution of the image in the slide. Example: 
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

4. Customise the email template content. Go to `<DIR_YOU_CLONED_THIS_REPO_INTO>/arches/settings_local.py` and edit/add a variable EXTRA_EMAIL_CONTEXT. It is expected to be a dictionary with the following keys:

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