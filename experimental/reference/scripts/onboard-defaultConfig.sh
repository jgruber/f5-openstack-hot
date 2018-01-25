#!/bin/bash

source /config/cloud/openstack/onboard_env

echo '******Overriding Default Configuration******'

/usr/bin/setdb provision.1nicautoconfig disable
/usr/bin/passwd admin "${bigip_admin_pwd}" >/dev/null 2>&1
/usr/bin/passwd root "${bigip_root_pwd}" >/dev/null 2>&1

mkdir -m 0755 -p /config/cloud/openstack
cd /config/cloud/openstack
echo "${bigip_admin_pwd}" >> /config/cloud/openstack/adminPwd
echo "${bigip_root_pwd}" >> /config/cloud/openstack/rootPwd

if [ -f /config/setup-staticMgmt.sh ]; then
    nohup sh -c '/config/setup-staticMgmt.sh' >> /var/log/setup-static-mgmt.log < /dev/null &
fi
