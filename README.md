# Arches for JU Excavations (Docker Deployment)

The official Docker configuration for deploying the [**Arches for JU Excavations Application**](https://github.com/Mare-Nostrum-Lab-UJ/arches-for-ju-excavations). 

This deployment stack, alongside the core application, was developed as part of the [**Mare Nostrum LAB Platform**](https://mn.cenagis.edu.pl) and is powered by the [**Arches Project**](https://www.archesproject.org). 

Special thanks to the original creators of [**arches-via-docker**](https://github.com/opencontext/arches-via-docker) (credited in the contributors sidebar) for the foundational Docker configurations used in this project.

## Setting Up Arches for JU Excavations on Your Machine
1. Clone this repository.
    ```bash
    git clone https://gitlab.cenagis.edu.pl/uavgeolab/mare-nostrum/arches-for-excavation-project.git
    ```
2. Create an .env file in the root of the cloned codebase, by copying the `edit_dot_env` file: 
    ``` bash
    cp edit_dot_env .env
    ```
3. Change essential env variables in the `.env` file:
    - *PUBLIC_PORT*: The port on your machine that will be exposed to the internet and used for web access (e.g., 80).
    - *DEPLOY_HOST*: The main domain name where your Arches instance will be accessible (e.g., arches.example.com).
    - *DOMAIN_NAMES*: A space-separated list of all domains and IPs that should resolve to your Arches instance (e.g., arches.example.com localhost 127.0.0.1).
    - *DJANGO_DEBUG*: True/true/False/false. Setting this option to True/true is useful during development, however for production-ready environments, it must strictly be set to False/false.
    - *ADMIN_PASSWORD*: Password for the superuser account described above.
4. Make sure you are on the default branch called **main**. If you are, start your Arches Project instance: 
    ```bash
    docker compose up --build -d
    ```
    Feel free to go grab yourself a coffee, it might take a while :).

     **If you encounter any issues** when trying to access your Arches instance in the browser, it is recommended to execute the following commands:
    ```bash
    docker exec -it arches npm run build_production
    ```
    ```bash
    docker exec -it arches python manage.py collectstatic --noinput --verbosity 2
    ```

    If the problem persists after executing those commands, run:
    ```bash
    docker compose restart
    ```

6. Register all Arches for JU Excavations custom reports, plugins and functions in your instance:
    ```bash
    docker exec -it arches ./register_extensions.sh
    ```

7. Import all Arches for JU Excavations ontology and resource models into your instance:
    ```bash
    docker exec -it arches python manage.py packages -o load_package -a arches_for_excavation -y
    ```

8. (Optional) Set up mailing backend for your arches instance, to do so overwrite variables listed below inside your `.env` file:
    - *EMAIL_PASSWORD*: Password for your email server. **If your password contains special characters (like '$'), wrap it in single quotes to avoid issues with Docker/Python parsing**.
    - *DEFAULT_FROM_EMAIL*: The display name and email address that will appear as the sender (e.g., <noreply@arches.example.com>').
    - *EMAIL_USE_TLS*: True/true/False/false
    - *EMAIL_USE_SSL*: True/true/False/false
    - *EMAIL_HOST*: The SMTP server address for sending emails (e.g., 'smtp.example.com').
    - *EMAIL_HOST_USER*: The username for authenticating with your SMTP server.
    - *EMAIL_PORT*: The port number for your SMTP server.
    
    After doing so, remember to restart your services in order for the system to acknowledge the changes:
    ```bash
    docker compose restart
    ```

## Customizing Your Arches for JU Excavations
1. Change the `.env` variables essential for this section:
    - *APP_TITLE*: The name displayed as page title as well as in the landing page header. Default: `Arches for JU Excavations`.
    - *EXCAVATION_NAME*: Name of the specific excavation site you are setting the Arches instance up for. It will be displayed as the title of the slides in the landing page. Default: `Arches for JU Excavations`.

2. Add your own logo and images for the slides in the landing page. Go to `<DIR_YOU_CLONED_THIS_REPO_INTO>\arches_for_excavation_project\media\img\landing`.
    - Place your logo in `\custom\project_logo.png`.
    - Place your first slide image in `\custom\landing_first.jpg`.
    - Place your second slide image in `\custom\landing_second.jpg`.
    - Place your third slide image in `\custom\landing_third.jpg`.

3. Customise the captions and attributions displayed in the landing page slides. Go to `<DIR_YOU_CLONED_THIS_REPO_INTO>\arches\settings_local.py` and edit/add a variable `LANDING_IMAGE_SLIDES_CONFIG`. It is expected to be a 3 element list of dictionaries, where each dictionary contains 2 key-value pairs. The first one is a caption to be displayed in the text box of a slide in the landing page, and the other is the attribution of the image in the slide. Example: 
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

4. Customise the email template content. Go to `<DIR_YOU_CLONED_THIS_REPO_INTO>\arches\settings_local.py` and edit/add a variable EXTRA_EMAIL_CONTEXT. It is expected to be a dictionary with the following keys:

    - *salutation*: The opening greeting string used in the email (e.g., "Hi").

    - *expiration*: A string defining how long the activation link remains valid (e.g., "24 hours").

    - *arches_project_name*: The title of your project instance.

    - *greeting*: The main body text of the email welcoming the user. Wrap this in Django's mark_safe() if you want to include custom HTML formatting or links.

    - *button_text*: The text displayed inside the main confirmation button (e.g., "Confirm").

    - *domain_url*: The domain variable (usually maps to _DOMAIN_URL) used to build the activation link.

    - *footer_strong_text*: Bolded text representing the institution or project name in the email footer. Wrap in mark_safe() to support HTML entities like &bull;.

    - *footer_additional_text*: Fine print, addresses, or contact details in the footer. Wrap in mark_safe() to support HTML entities like "&middot;".

    To add your own header and footer icons to the email template place them in: 

    `<DIR_YOU_CLONED_THIS_REPO_INTO>\arches_for_excavation_project\media\img\email\custom\email_header.png`

    and 

    `<DIR_YOU_CLONED_THIS_REPO_INTO>\arches_for_excavation_project\media\img\email\custom\email_footer.png`.
