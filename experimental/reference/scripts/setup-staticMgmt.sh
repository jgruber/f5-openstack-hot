#!/bin/bash

source /config/cloud/openstack/onboard_env

cidr_bits=$(echo $bigip_mgmt_cidr | cut -d/ -f2)
msg=""
stat="SUCCESS"
logFile="/var/log/setup-static-mgmt.log"

function check_mcpd_up() {
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
}

function restart_nic() {
    ifdown "$bigip_mgmt_interface_name" && ifup "$bigip_mgmt_interface_name"
    ip link set "$bigip_mgmt_interface_name" mtu "$bigip_mgmt_mtu"
}

function persiste_mtu() {
    echo "ip link set $bigip_mgmt_interface_name mtu $bigip_mgmt_mtu" >> /config/startup
}

function disable_mgmt_dhcp() {
    echo 'Disabling mgmt-dhcp...'
    if tmsh modify sys global-settings mgmt-dhcp disabled && tmsh save sys config ; then
        restart_nic
    else
        msg="Unable to set mgmt-dhcp to disabled."
        stat="FAILURE"
    fi
}

function create_mgmt_ip() {
    echo 'Creating mgmt - ip... '
    if ! tmsh create /sys management-ip "$bigip_mgmt_ip_address/$cidr_bits" ; then
        msg="$msg.. Unable to set mgmt-ip."
        stat="FAILURE"
    fi
}

function create_mgmt_gateway() {
    if [[ "$bigip_mgmt_gateway" != "" && "$bigip_mgmt_gateway" != "None" ]]; then
        echo 'Creating mgmt - gateway route...'
        if ! tmsh create sys management-route default gateway $bigip_mgmt_gateway ; then
            msg="$msg.. Unable to create a default gateway route."
            stat="FAILURE"
        fi
    fi
}

function add_dns_servers() {
    if [[ "$bigip_mgmt_dns_nameservers" != "" && "$bigip_mgmt_dns_nameservers" != "None" ]]; then
        echo 'Creating dns server entries...'
        nameservers=$(echo $bigip_mgmt_dns_nameservers | sed 's/[][]//g' | tr ',' ' ')
        # need to set this early in case we need to resolve hosts (e.g. we are downloading libs from github)
        tmsh modify sys dns name-servers add { $nameservers }
    fi
}

function manage_signal() {
    if [[ "$stat" == "FAILURE" ]]; then
        msg="Setup-staticMgmt command exited with error. See $logFile for details."
    else
        touch /config/cloud/openstack/staticMgmtReady
        msg="Setup-staticMgmt command exited without error."
    fi

    echo "$msg"

    if ! [[ "$os_wait_condition_static_mgmt" == "" || "$os_wait_condition_static_mgmt" == "None"  ]]; then
        data="{\"status\": \"${stat}\", \"reason\": \"${msg}\"}"
        cmd="$os_wait_condition_static_mgmt --data-binary '$data' --retry 5 --retry-max-time 300 --retry-delay 30"
        eval "$cmd"
    fi
}

function main () {
    date "+%Y-%m-%d %X %Z"
    echo 'Starting static network configuration for management NIC'

    check_mcpd_up
    disable_mgmt_dhcp
    create_mgmt_ip
    create_mgmt_gateway
    add_dns_servers
    tmsh save sys config
    restart_nic
    persiste_mtu
    manage_signal
}

main
