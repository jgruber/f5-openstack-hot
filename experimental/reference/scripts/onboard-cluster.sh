#!/bin/bash
echo '******Starting Cluster Configuration******'

source /config/cloud/openstack/onboard_env

msg=""
stat="FAILURE"
deviceName=$bigip_hostname

masterIp=$bigip_master_mgmt_ip_address
mgmtIp=$bigip_mgmt_ip_address
configSyncIp=$bigip_config_sync_ip
autoSync=$bigip_auto_sync
saveOnAutoSync=$bigip_save_on_auto_sync

if [[ "$autoSync" == "True" ]]; then
    autoSync="--auto-sync"

    if [[ "$saveOnAutoSync" == "True" ]]; then
        saveOnAutoSync="--save-on-auto-sync"
    else
        saveOnAutoSync=""
    fi
else
    autoSync=""
fi

isMaster=false
if [[ "$mgmtIp" == "$masterIp" ]]; then
    isMaster=true
fi

deviceCurr=$(tmsh list cm device | grep bigip1 -c)
if [[ "$deviceCurr" -gt 0 ]]; then
  echo 'Warning: DeviceName is showing as default bigip1. Manually changing'

  if [[ "$deviceName" == "" || "$deviceName" == "None"  ]]; then
    echo 'building hostname manually - no fqdn returned from neutron port assignment'
    dnsSuffix=$(/bin/grep search /etc/resolv.conf |n awk '{print $2}')
    hostName="host-$mgmtIp.$dnsSuffix"
  else
    deviceName=${deviceName%.}
  fi
  tmsh mv cm device bigip1 "$deviceName"
else
  hostName=$(tmsh list cm device one-line | awk '{print $3}')
  echo "Using hostName: $hostName"
  deviceName="$hostName"
fi

echo 'Configuring config-sync ip'
tmsh modify cm device "$deviceName" configsync-ip $configSyncIp unicast-address { { effective-ip $configSyncIp effective-port 1026 ip $configSyncIp } }

if [[ "$isMaster" == true ]] ; then
echo 'Config-Sync Master device'
    f5-rest-node /config/cloud/openstack/node_modules/f5-cloud-libs/scripts/cluster.js \
    -o /var/log/onboard-cluster.log \
    --log-level debug \
    --host $bigip_mgmt_ip_address \
    --user admin \
    --password-url file:///config/cloud/openstack/adminPwd \
    --port $bigip_management_port \
    --create-group \
    --device-group $bigip_device_group \
    --sync-type $bigip_sync_type \
    --device "$deviceName" \
    --network-failover \
    "$autoSync" \
    "$saveOnAutoSync"
else
echo 'Config-Sync Secondary device'
    f5-rest-node /config/cloud/openstack/node_modules/f5-cloud-libs/scripts/cluster.js \
    -o /var/log/onboard-cluster.log \
    --log-level debug \
    --host $bigip_mgmt_ip_address \
    --user admin \
    --password-url file:///config/cloud/openstack/adminPwd \
    --port $bigip_management_port \
    --join-group \
    --device-group $bigip_device_group \
    --sync \
    --remote-host $bigip_master_mgmt_ip_address \
    --remote-user admin \
    --remote-password-url file:///config/cloud/openstack/adminPwd

fi

onboardClusterErrorCount=$(tail /var/log/onboard-cluster.log | grep "cluster failed" -i -c)

if [ "$onboardClusterErrorCount" -gt 0 ]; then
    msg="Onboard-cluster command exited with error. See /var/log/onboard-cluster.log for details."
else
    stat="SUCCESS"
    msg="Onboard-cluster command exited without error."
fi


msg="$msg *** Instance: $deviceName"
echo "$msg"
data="{\"status\": \"${stat}\", \"reason\": \"${msg}\"}"
cmd="$os_wait_condition_onboard_cluster_complete --data-binary '$data' --retry 5 --retry-max-time 300 --retry-delay 30"
eval "$cmd"



