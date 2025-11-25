### Instructions regarding naming/placement conventions for future developers to follow

1. Arches Extensions

    1. Reports <br/>
    As reports require 3 files to be correctly registered and used, we recommend sticking to our convention and naming the appropriate fiels according to notations listed below:
    
        - `arches_slocal\arches_slocal\media\js\report\smy-report.js` -> **kebab case**
        - `arches_slocal\arches_slocal\reports\my-report.json` -> **kebab case**
        - `arches_slocal\arches_slocal\templates\views\report-templates\my_report` -> **camel case**

        We also currently decided to implement a walkaround allowing to add custom tabs and logic to tabbed-report, located at:                 `arches_slocal\arches_slocal\media\js\viewmodels\mixins\tab-report-setup.js`
        for reference usage of **setupTabbedReport** checkout `arches_slocal\arches_slocal\media\js\reports\resource-3d-report.js`

    2. 

2. Custom knockout components 

    A custom component's code parts should be placed and named as following:
    1. JavaScript source code -> `arches_slocal\arches_slocal\media\js\my_component` (folder name in **camel case**).
    2. JavaSript entry point file, with component registration logic -> `arches_slocal\arches_slocal\media\js\views\components\custom\my-component.js` (file name in **kebab case**).
    3. CSS file/s -> `arches_slocal\arches_slocal\media\css\my_component` (folder name in **camel case**), and referenced inside **entry point file**. In case you only define one css file, you should use the name **index.css**.
    4. Html template -> `arches_slocal\arches_slocal\templates\views\components\custom\my_viewer.htm` (file name in **camel case**).


