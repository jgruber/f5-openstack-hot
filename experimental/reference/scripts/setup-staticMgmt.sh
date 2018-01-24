#!/bin/bash

nic="__nic__"
mtu="__mtu__"
addr="__addr__"
cidr_bits=$(echo "__cidr__" | cut -d/ -f2)
gateway="__gateway__"
dns="__dns__"
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
    ifdown "$nic" && ifup "$nic"
    ip link set "$nic" mtu "$mtu"
}

function persiste_mtu() {
    echo "ip link set $nic mtu $mtu" >> /config/startup
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
    if ! tmsh create /sys management-ip "$addr/$cidr_bits" ; then
        msg="$msg.. Unable to set mgmt-ip."
        stat="FAILURE"
    fi
}

function create_mgmt_gateway() {
    if [[ "$gateway" != "" && "$gateway" != "None" ]]; then
        echo 'Creating mgmt - gateway route...'
        if ! tmsh create sys management-route default gateway $gateway ; then
            msg="$msg.. Unable to create a default gateway route."
            stat="FAILURE"
        fi
    fi
}

function add_dns_servers() {
    if [[ "$dns" != "" && "$dns" != "None" ]]; then
        echo 'Creating dns server entries...'
        nameservers=$(echo $dns | sed 's/[][]//g' | tr ',' ' ')
        # need to set this early in case we need to resolve hosts (e.g. we are downloading libs from github)
        tmsh modify sys dns name-servers add { $nameservers }
    fi
}

function manage_signal() {
    if [[ "$stat" == "FAILURE" ]]; then
        echo "$msg"
        msg="Setup-staticMgmt command exited with error. See $logFile for details."
    else
        touch /config/cloud/openstack/staticMgmtReady
        msg="Setup-staticMgmt command exited without error."
    fi

    wc_notify --data-binary '{"status": "'"$stat"'", "reason":"'"$msg"'"}' --retry 5 --retry-max-time 300 --retry-delay 30
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
