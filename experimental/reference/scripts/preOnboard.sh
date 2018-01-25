#!/bin/bash
echo '******STARTING PRE-ONBOARD******'

source /config/cloud/openstack/onboard_env


echo $bigiq_license_pwd > /config/cloud/openstack/bigIqPwd
chown root:root /config/cloud/openstack/bigIqPwd
chmod 0644 /config/cloud/openstack/bigIqPwd

if [[ "$f5_verify_hash_url_override" != "" && "$f5_verify_hash_url_override" != "None" ]]; then
    curl ${f5_verify_hash_url_override} > /config/verifyHash
fi

msg=""
stat=""

#*************************************************************************************************
echo 'Starting MCP status check'
checks=0
while [ $checks -lt 120 ]; do echo checking mcpd
    if tmsh -a show sys mcp-state field-fmt | grep -q running; then
        echo mcpd ready
        break
    fi
    echo mcpd not ready yet
    let checks=checks+1
    sleep 10
done

echo 'loading verifyHash script'
if ! tmsh load sys config merge file /config/verifyHash; then
    echo cannot validate signature of /config/verifyHash
    msg="Unable to validate verifyHash."
fi
echo 'loaded verifyHash'
declare -a filesToVerify=("/config/cloud/openstack/f5-cloud-libs.tar.gz" "/config/cloud/openstack/f5-cloud-libs-openstack.tar.gz")
for fileToVerify in "${filesToVerify[@]}"
do
    echo verifying "$fileToVerify"
    if ! tmsh run cli script verifyHash "$fileToVerify"; then
        echo "$fileToVerify" is not valid
        msg="Unable to verify one or more files."
    fi
    echo verified "$fileToVerify"
done

#*************************************************************************************************
if [[ "$msg" == "" ]]; then
    echo 'Preparing CloudLibs'
    mkdir -p /config/cloud/openstack/node_modules
    tar xvfz /config/cloud/openstack/f5-cloud-libs.tar.gz -C /config/cloud/openstack/node_modules
    tar --warning=no-unknown-keyword -zxf /config/cloud/openstack/f5-cloud-libs-openstack.tar.gz -C /config/cloud/openstack/node_modules/f5-cloud-libs/node_modules > /dev/null
    touch /config/cloud/openstack/cloudLibsReady
fi

#*************************************************************************************************
echo 'Configuring access to cloud-init data'
configDriveSrc=$(blkid -t LABEL="config-2" -odevice)
configDriveDest="/mnt/config"

if [[ "$os_use_config_drive" == "True" ]]; then
    echo 'Configuring Cloud-init ConfigDrive'
    mkdir -p $configDriveDest
    if mount "$configDriveSrc" $configDriveDest; then
        echo 'Adding SSH Key from Config Drive'
        if sshKey=$(python -c "import sys, json; print json.load(sys.stdin)['public_keys']['$os_ssh_key_name']" <"$configDriveDest"/openstack/latest/meta_data.json) ; then
            echo "$sshKey" >> /root/.ssh/authorized_keys
        else
            msg="Pre-onboard failed: Unable to inject SSH key from config drive."
            echo "$msg"
        fi
    else
        msg="Pre-onboard failed: Unable to mount config drive."
        echo "$msg"
    fi

else
    echo 'Adding SSH Key from Metadata service'
    declare -r tempKey="/config/cloud/openstack/os-ssh-key.pub"
    if curl http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key -s -f --retry 5   --retry-max-time 300 --retry-delay 10 -o $tempKey ; then
        (head -n1 $tempKey) >> /root/.ssh/authorized_keys
        rm $tempKey
    else
        msg="Pre-onboard failed: Unable to inject SSH key from metadata service."
        stat="FAILURE"
        echo "$msg"
    fi
fi

#*************************************************************************************************
#buffer wait before sending heat signal
#sleep 120

if [[ "$msg" == "" ]]; then
    stat="SUCCESS"
    msg="Pre-onboard completed without error."
else
    stat="FAILURE"
    msg="Last Error:$msg . See /var/log/preOnboard.log for details."
fi

if ! [[ "$os_wait_condition_onboard_complete" == "" || "$os_wait_condition_onboard_complete" == "None"  ]]; then
    data="{\"status\": \"${stat}\", \"reason\": \"${msg}\"}"
    cmd="$os_wait_condition_onboard_complete --data-binary '$data' --retry 5 --retry-max-time 300 --retry-delay 30"
    eval "$cmd"
fi

echo "$msg"
echo '******PRE-ONBOARD DONE******'
