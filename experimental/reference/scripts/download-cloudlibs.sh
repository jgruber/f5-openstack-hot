#!/bin/bash
            
source /config/cloud/openstack/onboard_env

if [[ "$f5_cloudlibs_url_override" == "None" ]]; then
    cloudlibsUrl="https://raw.githubusercontent.com/f5Networks/f5-cloud-libs/${f5_cloudlibs_tag}/dist/f5-cloud-libs.tar.gz"
else
    cloudlibsUrl=${f5_cloudlibs_url_override}
fi
echo "******Starting Download for f5-cloud-libs from ${cloudlibsUrl} ******"
curl -o /config/cloud/openstack/f5-cloud-libs.tar.gz ${cloudlibsUrl}

if [[ "$f5_cloudlibs_os_url_override" == "None" ]]; then
    cloudlibsOsUrl="https://raw.githubusercontent.com/f5Networks/f5-cloud-libs-openstack/${f5_cloudlibs_os_tag}/dist/f5-cloud-libs-openstack.tar.gz"
else
    cloudlibsOsUrl=${f5_cloudlibs_os_url_override}
fi
echo "******Starting Download for f5-cloud-libs-openstack from ${cloudlibsOsUrl} ******"
curl -o /config/cloud/openstack/f5-cloud-libs-openstack.tar.gz ${cloudlibsOsUrl}

touch /config/cloud/openstack/cloudLibsDownloadReady
