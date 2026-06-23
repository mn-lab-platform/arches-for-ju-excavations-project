# THE TALES OF ARCHES PROJECT

## 1. Setting up arches on your brand new machine
1. Clone the source code from Arches for Excavation repo: 
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
    - *EMAIL_PASSWORD*: Password for your email server. **If your password contains special characters (like '$'), wrap it in single quotes to avoid issues with Docker/Python parsing**.
    - *DEFAULT_FROM_EMAIL*: The display name and email address that will appear as the sender (e.g., <noreply@arches.example.com>').
    - *EMAIL_USE_TLS*: True/true/False/false
    - *EMAIL_USE_SSL*: True/true/False/false
    - *EMAIL_HOST*: The SMTP server address for sending emails (e.g., 'smtp.example.com').
    - *EMAIL_HOST_USER*: The username for authenticating with your SMTP server.
    - *EMAIL_PORT*: The port number for your SMTP server.
4. Make sure you are on the default branch called **prod**. If you are, start your Arches Project instance: 
    ```
    docker compose up --build -d
    ```
    Feel free to go grab yourself a coffee, it might take a while :). <br>
     **In case of any issues** that may appear when trying to access your Arches instance in the browser (issues that are not caused by your hosting provider) it is recommended to execute the following commands:
    ```
    docker exec -it arches npm install
    ```
    ```
    docker exec -it arches npm run build_development
    ```
    ```
    docker exec -it arches python manage.py collectstatic --noinput --verbosity 2
    ```

5. In case by now you can see the arches landing page, you got yourself a working Arches Project Instance. If something still doesn't work refer to the X section of this document where hopefully you will find a solution to your issue.

6. Register the custom plugins and reports. Execute the automatic registration script:
    ```
    ./register_all.sh
    ```
    **If you plan on adding Resource Models that already have a custom report assigned to them, please do copy the logs produced by the `register_all.sh` script, more on that in the next point.**

7. (Optional) Assign the template ids of the custom reports to designated Resource Models. We will walk through the process of validating the Resource Model after registering the reports on an example of Digital Resource 3D model. A report template for the Digital Resource 3D is called `digital-resource-3d-report`. Find the name of the report in the logs that you have saved as requested in the previous step. You should find the lines that look like this: 
    ```
    Registering report: /arches_app/arches_slocal/arches_slocal/reports/digital-resource-3d-report.json
    Registering report template with templateid: 9416c739-8c48-4345-b4fb-ffb3c1753b62
    ```
    The second line is the important part - it contains the **templateid** that you'll need to copy and paste into your Resource Model's JSON file.
    To do that open the Digital Resource 3D JSON file and search for the regex `template_id`. You'll find a line like this: <br>
    ```
    "template_id": "7c900fc1-73ae-4661-b524-7dc7cd7858dc"
    ```
    The line will probably contain the previously generated template_id of the custom report. All you need to do now is **assign your new template id eg. 9416c739-8c48-4345-b4fb-ffb3c1753b62 for the key "template_id" and save the file**. After doing so you can successfully upload Digital Resource 3D Model (your Resource Model).
## 2. Development in Arches for Excavation