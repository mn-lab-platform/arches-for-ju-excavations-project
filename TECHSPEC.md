### Instructions regarding naming/placement conventions for future developers to follow

1. Arches Extensions Naming convention <br/>
    1. Reports <br/>
    As reports require 3 files to be correctly registered and used, we recommend sticking to our convention and naming the appropriate fiels according to notations listed below:
    
        - `arches_slocal\arches_slocal\media\js\report\smy-report.js` -> **kebab case**
        - `arches_slocal\arches_slocal\reports\my-report.json` -> **kebab case**
        - `arches_slocal\arches_slocal\templates\views\report-templates\my_report` -> **camel case**

    We also currently decided to implement a walkaround allowing to add custom tabs and logic to tabbed-report, located at:                 `arches_slocal\arches_slocal\media\js\viewmodels\mixins\tab-report-setup.js`
    for reference usage of `setupTabbedReport` checkout 
    2. 
