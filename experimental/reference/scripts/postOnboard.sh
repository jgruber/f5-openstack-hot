#!/bin/bash

source /config/cloud/openstack/onboard_env

err=0
msg="Post-onboard completed without error."
stat="SUCCESS"

function cleanup() {
    shred -u -z  /config/cloud/openstack/rootPwd

    if [[ "$f5_keep_admin" == "False" ]]; then
       shred -u -z /config/cloud/openstack/adminPwd
    fi

    if [[ "$f5_keep_bigiq" == "False" ]]; then
      shred -u -z /config/cloud/openstack/bigIqPwd
    fi

    if [[ "$f5_keep_config_drive" == "False" ]]; then
        mountFound=$(grep '/mnt/config' /proc/mounts -c)
        if [[ $mountFound == 1 ]] ; then
            umount /mnt/config
            rmdir /mnt/config
        fi
    fi
}

function run_custom_config() {
    echo 'Running custom configuration commands, if any'
    ### START CUSTOM CONFIGURATION ###

    ### END CUSTOM CONFIGURATION ###`
}

function send_heat_signal() {
    echo "$msg"
    data="{\"status\": \"${stat}\", \"reason\": \"${msg}\"}"
    cmd="$os_wait_condition_onboard_complete --data-binary '$data' --retry 5 --retry-max-time 300 --retry-delay 30"
    eval "$cmd"
}

function main() {
    echo '*****POST-ONBOARD STARTING******'

    if ! cleanup ; then
        err+=1
    fi

    if ! run_custom_config ; then
        err+=1
    fi

    if [[ err -ne 0 ]]; then
        msg="Post-onboard command(s) exited with an error signal."
        stat="FAILURE"
    fi

    send_heat_signal

    echo '*****POST-ONBOARD DONE******'
}

main
