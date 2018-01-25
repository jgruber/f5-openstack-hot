#!/bin/bash
echo '*****ONBOARD STARTING******'

source /config/cloud/openstack/onboard_env

#vars
#some default values set by heat str_replace

#licensing
licenseKey=$bigip_license_key
licenseOpt="--license"
addOnLicenses=$bigip_addon_license_keys
bigIqHost=$bigiq_license_host_ip
bigIqUsername=$bigiq_license_username
bigIqLicPool=$bigiq_license_pool
bigIqUseAltMgmtIp=$bigiq_use_alt_bigip_mgmt_ip
bigIqAltMgmtIp=$bigiq_alt_bigip_mgmt_ip
bigIqAltMgmtPort=$bigiq_alt_bigip_mgmt_port
bigIqPwdUri="file:///config/cloud/openstack/bigIqPwd"
bigIqMgmtIp=""
bigIqMgmtPort=""

dns_list=($(echo $bigip_servers_dns | sed -e 's/[][]//g' -e 's/"//g' -e 's/,//g'))
dns=""
for i in ${dns_list[@]}; do dns="${dns}--dns $i "; done
dns=$(echo $dns|sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

ntp_list=($(echo $bigip_servers_ntp | sed -e 's/[][]//g' -e 's/"//g' -e 's/,//g'))
ntp=""
for i in ${ntp_list[@]}; do ntp="${ntp}--ntp $i "; done
ntp=$(echo $ntp|sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

modules_list=($(echo $bigip_modules | sed -e 's/[][]//g' -e 's/"//g' -e 's/,//g'))
modules=""
for i in ${modules_list[@]}; do ="${modules}--module $i "; done
modules=$(echo $modules|sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

addons_list=($(echo $bigip_addon_license_keys | sed -e 's/[][]//g' -e 's/"//g' -e 's/,//g'))
addOnLicenses=""
for i in ${addons_list[@]}; do ="${addOnLicenses}--add-on $i "; done
addOnLicenses=$(echo $addOnLicenses|sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

hostName=$bigip_hostname
mgmtPortId=$os_management_port_id
adminPwd=""
newRootPwd=""
oldRootPwd=""
msg=""
stat="FAILURE"
logFile="/var/log/onboard.log"

allowUsageAnalytics=$f5_ua_allow
templateName=$f5_ua_template_name
templateVersion=$f5_ua_template_version
cloudLibsTag=$f5_ua_cloudlibs_tag
custId=$(echo "f5_ua_project_id"|sha512sum|cut -d " " -f 1)
deployId=$(echo "f5_ua_stack_id"|sha512sum|cut -d " " -f 1)
region=$f5_ua_region
metrics=""
metricsOpt=""
licenseType=$f5_ua_license_type

function set_vars() {
    if [ "$addOnLicenses" == "--add-on None" ]; then
        addOnLicenses=""
    fi

    if [ "$dns" == "--dns None" ]; then
        dns=""
    fi

    if [ "$ntp" == "--ntp None" ]; then
        ntp=""
    fi

    if [ "$modules" == "--module None" ]; then
        modules=""
    fi

    if [ "$licenseType" == "BIGIQ" ]; then
        if [ "$bigIqUseAltMgmtIp" == "True" ]; then
            bigIqMgmtIp="--big-ip-mgmt-address ${bigIqAltMgmtIp}"

            if [ "$bigIqAltMgmtPort" != "None" ]; then
                bigIqMgmtPort="--big-ip-mgmt-port ${bigIqAltMgmtPort}"
            fi
        fi
        licenseOpt="--license-pool"
        license="--license-pool-name ${bigIqLicPool} --big-iq-host ${bigIqHost} --big-iq-user ${bigIqUsername} --big-iq-password-uri ${bigIqPwdUri} ${bigIqMgmtIp} ${bigIqMgmtPort}"
    else
        if [ "${licenseKey,,}" == "none" ]; then
            license=""
            licenseOpt=""
        else
            license="${licenseKey}"
        fi
    fi

    if [[ "$hostName" == "" || "$hostName" == "None" ]]; then
        echo 'using mgmt neutron portid as hostname - no fqdn returned from neutron port assignment'
        # get first matching domain
        dnsSuffix=$(/bin/grep search /etc/resolv.conf | awk '{print $2}')
        if [[ "$dnsSuffix" == "" ]]; then
            dnsSuffix="openstacklocal"
        fi
            hostName="host-$mgmtPortId.$dnsSuffix"
    else
        #remove trailing . from fqdn
        hostName=${hostName%.}
    fi

    onboardRun=$(grep "Starting Onboard call" -i -c -m 1 "$logFile" )
    if [ "$onboardRun" -gt 0 ]; then
        echo 'WARNING: onboard already previously ran.'
        oldRootPwd=$(</config/cloud/openstack/rootPwd)
    else
        oldRootPwd=$(</config/cloud/openstack/rootPwd)
    fi

    adminPwd=$(</config/cloud/openstack/adminPwd)
    newRootPwd=$(</config/cloud/openstack/rootPwd)

    if [[ "$allowUsageAnalytics" == "True" ]]; then
        bigIpVersion=$(tmsh show sys version | grep -e "Build" -e " Version" | awk '{print $2}' ORS=".")
        metrics="customerId:${custId},deploymentId:${deployId},templateName:${templateName},templateVersion:${templateVersion},region:${region},bigIpVersion:${bigIpVersion},licenseType:${licenseType},cloudLibsVersion:${cloudLibsTag},cloudName:openstack"
        metricsOpt="--metrics"
        echo "$metrics"
    fi
}

function set_adminPwd() {
    tmsh modify auth user admin shell tmsh password "$adminPwd"
}

function onboard_run() {
    echo 'Starting Onboard call'
    if f5-rest-node /config/cloud/openstack/node_modules/f5-cloud-libs/scripts/onboard.js \
        $metricsOpt $metrics \
        $addOnLicenses \
        $dns \
        --host localhost \
        --hostname "$hostName" \
        $licenseOpt $license \
        --log-level debug \
        $modules\
        $ntp \
        --output "$logFile" \
        --port $bigip_management_port \
        --set-root-password old:"$oldRootPwd",new:"$newRootPwd" \
        --tz UTC \
        --user admin --password-url file:///config/cloud/openstack/adminPwd ; then

        licenseExists=$(tail /var/log/onboard.log -n 25 | grep "Fault code: 51092" -i -c)

        if [ "$licenseExists" -gt 0 ]; then
            msg="Onboard completed but licensing failed. Error 51092: This license has already been activated on a different unit."
            stat="SUCCESS"
        else
            errorCount=$(tail /var/log/onboard.log | grep "BIG-IP onboard failed" -i -c)

            if [ "$errorCount" -gt 0 ]; then
                msg="Onboard command failed. See logs for details."
            else
                msg="Onboard command exited without error."
                stat="SUCCESS"
            fi

        fi
    else
        msg='Onboard exited with an error signal.'
    fi
}

function send_heat_signal() {
    echo "$msg"
    if ! [[ "$os_wait_condition_onboard_complete" == "" || "$os_wait_condition_onboard_complete" == "None"  ]]; then
        data="{\"status\": \"${stat}\", \"reason\": \"${msg}\"}"
        cmd="$os_wait_condition_onboard_complete --data-binary '$data' --retry 5 --retry-max-time 300 --retry-delay 30"
        eval "$cmd"
    fi

}

function main() {
    set_vars
    set_adminPwd
    onboard_run
    send_heat_signal
}

main
