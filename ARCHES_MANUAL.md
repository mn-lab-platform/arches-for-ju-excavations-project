# THE TALES OF ARCHES PROJECT

## 1. Setting up Arches for Excavation on your machine
1. Clone the source code from the Arches for Excavation repo: 
    ```
    git clone --recurse-submodules https://gitlab.cenagis.edu.pl/uavgeolab/mare-nostrum/arches.git
    ```
2. Create an .env file by copying the `edit_dot_env` file: 
    ```
    cp edit_dot_env .env
    ```
3. Change essential env variables in the `.env` file:
    - *PUBLIC_PORT*: The port on your machine that will be exposed to the internet and used for web access (e.g., 80).
    - *DEPLOY_HOST*: The main domain name where your Arches instance will be accessible (e.g., arches.example.com).
    - *DOMAIN_NAMES*: A space-separated list of all domains and IPs that should resolve to your Arches instance (e.g., arches.example.com localhost 127.0.0.1).
    - *DJANGO_DEBUG*: True/true/False/false. Setting this option to True/true is useful during development, however, for production-ready environments, it must strictly be set to False/false.
    - *ADMIN_USERNAME*: Superuser login that you will use to log into your Arches for Excavation instance, as well as the admin panel in the browser.
    - *ADMIN_PASSWORD*: Password for the superuser account described above.
4. Make sure you are on the default branch called **main**. If you are, start your Arches Project instance: 
    ```
    docker compose up --build -d
    ```
    Feel free to go grab yourself a coffee, it might take a while :). <br>
     **If you encounter any issues** when trying to access your Arches instance in the browser (issues that are not caused by your hosting provider) it is recommended to execute the following commands:
    ```
    docker exec -it arches npm install
    ```
    ```
    docker exec -it arches npm run build_development
    ```
    ```
    docker exec -it arches python manage.py collectstatic --noinput --verbosity 2
    ```

    If the problem persists after executing those commands (for example search page is loading infinitely) execute:
    ```
    docker compose restart
    ```

5. If something still doesn't work, compare your error message to those (not very maturely) listed inside `CAPTAINS_DIARY.md`. For yet to be diagnosed reason arches seems to "misfire" silently sometimes during webpack setup. First sign of such misfire is the inability to log in using the credentials you set in your `.env` file. In case you stuck to the default login and password (**NOT RECOMMENDED**), easiest way to tell something went wrong during the startup is check whether your instance contains some resource models in **Arches Designer tab** (`<YOUR-DOMAIN>/graph/`). If you dont see any resource models, simply execute:
    ```
    docker compose restart
    ```

6. In case by now you can see the arches landing page, you got yourself a working Arches Project Instance. It should contain (TODO: List of available plugins + resource models).

7. (Optional) Set up mailing backend for your arches instance, to do so overwrite variables listed below inside your `.env` file:
    - *EMAIL_PASSWORD*: Password for your email server. **If your password contains special characters (like '$'), wrap it in single quotes to avoid issues with Docker/Python parsing**.
    - *DEFAULT_FROM_EMAIL*: The display name and email address that will appear as the sender (e.g., <noreply@arches.example.com>').
    - *EMAIL_USE_TLS*: True/true/False/false
    - *EMAIL_USE_SSL*: True/true/False/false
    - *EMAIL_HOST*: The SMTP server address for sending emails (e.g., 'smtp.example.com').
    - *EMAIL_HOST_USER*: The username for authenticating with your SMTP server.
    - *EMAIL_PORT*: The port number for your SMTP server. <br> 
    
    After doing so remember to restart your services in order for the system to acknowledge the changes:
    ```
    docker compose restart
    ```
    or to be completely sure:
    ```
    docker compose up -d
    ```

## 2. Customizing your Arches for Excavation instance
1. Change the `.env` variables essential for this section:
    - *APP_TITLE*: The name displayed as page title as well as in the landing page header. Default: `Arches for Excavation`.
    - *EXCAVATION_NAME*: Name of the specific excavation site you are setting the arches instance up for. It will be displayed as the title of the slides in the landing page. Default: `Arches for Excavation`.
    - *CUSTOM_LANDING_MEDIA*: True/true/False/false; Set to True/true in case you want to provide your own project logo as well as photos for the slides in the landing page.

2. Add your own logo and images for the slides in the landing page. Remember to set the *CUSTOM_LANDING_MEDIA* variable to True/true in your `.env` file. If you did, go to `{ARCHES_PROJECT}\{ARCHES_PROJECT}\media\img\landing` and create a new directory called `custom`. 
    - Place your logo in `\custom\project_logo.png`.
    - Place your first slide image in `\custom\landing_first.jpg`.
    - Place your second slide image in `\custom\landing_second.jpg`.
    - Place your third slide image in `\custom\landing_third.jpg`.

3. Customise the captions displayed in the landing page slides. Go to `settings_local.py` and edit/add a variable `IMAGE_SLIDES_CAPTIONS`. It is expected to be a 3 element list of strings, where each string is a caption to be displayed in the text box of a slide in the landing page. Example: 
    ```
    IMAGE_SLIDES_CAPTIONS = [
        "Thelpousa was an Arcadian polis located approximately 25 km east of ancient Olympia.",
        "It was situated in the lower Ladon valley, north of the modern village of Toumbitsi.",
        "The site played an important role in the region's ancient history and landscape."
    ]
    ```

4. Customise the email template content. Go to settings_local.py and edit/add a variable EXTRA_EMAIL_CONTEXT. It is expected to be a dictionary with the following keys:

    - *salutation*: The opening greeting string used in the email (e.g., "Hi").

    - *expiration*: A string defining how long the activation link remains valid (e.g., "24 hours").

    - *arches_project_name*: The title of your project instance. Typically maps to the APP_TITLE variable.

    - *greeting*: The main body text of the email welcoming the user. Wrap this in Django's mark_safe() if you want to include custom HTML formatting or links.

    - *button_text*: The text displayed inside the main call-to-action confirmation button (e.g., "Confirm").

    - *domain_url*: The domain variable (usually maps to _DOMAIN_URL) used to build the activation link.

    - *footer_strong_text*: Bolded text representing the institution or project name in the email footer. Wrap in mark_safe() to support HTML entities like &bull;.

    - *footer_additional_text*: Fine print, addresses, or contact details in the footer. Wrap in mark_safe() to support HTML entities like "&middot;".

    Email template created by us requires providing 2 icons that will be placed in the header and footer of the email. Place the icons in: `{ARCHES_PROJECT}\{ARCHES_PROJECT}\media\img\mailing\footer_logo.png` and `{ARCHES_PROJECT}\{ARCHES_PROJECT}\media\img\mailing\header_logo.png`.

