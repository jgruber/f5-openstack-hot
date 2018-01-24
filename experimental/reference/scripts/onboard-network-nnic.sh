#!/bin/bash
echo '******Starting Additional Network Configuration******'

default_gateway="__default_gateway__"
vlan_params=""
selfip_params=""
vlan_name=""

logFile="/var/log/onboard-network.log"
gateway_opt=""
msg=""
stat="FAILURE"


function set_vlan_params() {
    local vlan_opt=""
    local vlan=""

    if [[ "$vlan_nic" == "" ]]; then
        vlan_nic_ctr=$(( vlan_nic_index + 1 ))
        vlan_nic="1.${vlan_nic_ctr}"
    fi

    if [[ "$vlan_name" == "None" || "$vlan_name" == "" ]]; then
        vlan_name="${vlan_nic}_vlan"
    fi

    if [[ "$vlan_create" == "True" ]]; then
        if [ "$vlan_mtu" == "0" ]; then
            vlan_mtu=""
        else
            vlan_mtu=",mtu:$vlan_mtu"
        fi

        if [ "$vlan_tag" == "None" ]; then
            vlan_tag=""
        else
            vlan_tag=",tag:${vlan_tag}"
        fi
        vlan="name:${vlan_name},nic:${vlan_nic}${vlan_mtu}${vlan_tag}"
        vlan_opt="--vlan"
        vlan_params="${vlan_params} ${vlan_opt} ${vlan}"
    else
        vlan=""
        vlan_opt=""
        vlan_params="${vlan_params}"
    fi

}

function set_selfip_params() {
    case "$self_port_lockdown" in
        " " | "" | "None" )
            self_port_lockdown=",allow:default"
            ;;
        * )
            self_port_lockdown=",allow:${self_port_lockdown//;/ }"
            ;;
    esac

        # "allow-default" )
        #     self_port_lockdown=",allow:default"
        #     ;;
        # ### NOTE:
        # ### To be supported in future cloud-libs fix
        # # "allow-all" )
        # #     self_port_lockdown=",allow:all"
        # #     ;;
        # # "allow-none" )
        # #     self_port_lockdown=",allow:none"
        # #     ;;
    self_port_lockdown="${self_port_lockdown//allow-default/default}"
    self_port_lockdown="${self_port_lockdown//allow-all/all}"
    self_port_lockdown="${self_port_lockdown//allow-none/none}"

    if [[ "$self_ip_name" == "None" || "$self_ip_name" == "" ]]; then
        self_ip_name="${vlan_name}_self"
    fi

    selfip_params="${selfip_params} --self-ip name:${self_ip_name},address:${self_ip}/${self_ip_prefix},vlan:${vlan_name}""'""${self_port_lockdown}""'"
}

function set_vars() {

    vlan_creates='__network_vlan_create__'
    vlan_names='__network_vlan_name__'
    vlan_tags='__network_vlan_tag__'
    vlan_mtus='__network_vlan_mtu__'
    vlan_nics='__network_vlan_nic__'
    vlan_nic_count='__network_vlan_nic_count__'

    # sanitize artifact [ ]  generated by heat for the list
    vlan_creates="${vlan_creates:1:${#vlan_creates}-2}"
    vlan_names=${vlan_names:1:${#vlan_names}-2}
    vlan_tags=${vlan_tags:1:${#vlan_tags}-2}
    vlan_mtus=${vlan_mtus:1:${#vlan_mtus}-2}
    vlan_nics=${vlan_nics:1:${#vlan_nics}-2}

    self_port_lockdowns='__network_self_port_lockdown__'
    self_ips='__network_self_ip_addr__'
    self_ip_names='__network_self_name__'
    self_ip_cidrs='__network_self_cidr_block__'

    # sanitize artifact [ ]  generated by heat for the list
    self_port_lockdowns=${self_port_lockdowns:1:${#self_port_lockdowns}-2}
    self_ips=${self_ips:1:${#self_ips}-2}
    self_ip_names=${self_ip_names:1:${#self_ip_names}-2}
    self_ip_cidrs=${self_ip_cidrs:1:${#self_ip_cidrs}-2}

    OIFS="$IFS"
    IFS=', '
    # sanitize artifact " generated by heat and read value into array var
    read -r -a creates <<< "${vlan_creates//\"}"
    read -r -a vlans <<< "${vlan_names//\"}"
    read -r -a tags <<< "${vlan_tags//\"}"
    read -r -a mtus <<< "${vlan_mtus//\"}"
    read -r -a nics <<< "${vlan_nics//\"}"
    read -r -a portLockdowns <<< "${self_port_lockdowns//\"}"
    read -r -a ips <<< "${self_ips//\"}"
    read -r -a ipNames <<< "${self_ip_names//\"}"
    read -r -a cidrs <<< "${self_ip_cidrs//\"}"
    IFS="$OIFS"

    # echo "$creates"
    # echo "$vlans"
    # echo "$tags"
    # echo "$mtus"
    # echo "$nics"
    # echo "$portLockdowns"
    # echo "$ips"
    # echo "$ipNames"
    # echo "$cidrs"

    local counter=0
    while [[ $counter -lt $vlan_nic_count ]]; do
        vlan_create=${creates[$counter]}
        vlan_name=${vlans[$counter]}
        vlan_tag=${tags[$counter]}
        vlan_mtu=${mtus[$counter]}
        vlan_nic=${nics[$counter]}
        vlan_nic_index=$counter
        self_port_lockdown=${portLockdowns[$counter]}
        self_ip=${ips[$counter]}
        self_ip_name=${ipNames[$counter]}
        self_ip_cidr=${cidrs[$counter]}
        self_ip_prefix=${self_ip_cidr#*/}

        set_vlan_params
        set_selfip_params

        let counter+=1;
    done

    if [[ "$default_gateway" != "None" && "$default_gateway" != "" ]]; then
        default_gateway="${default_gateway}"
        gateway_opt="--default-gw"
    else
        default_gateway=""
        gateway_opt=""
    fi

    echo "Vlan params: $vlan_params"
    echo "SelfIp params: $selfip_params"
}

function onboard_network_run() {
    cmd="f5-rest-node /config/cloud/openstack/node_modules/f5-cloud-libs/scripts/network.js "
    cmd+="-o ${logFile} "
    cmd+="--log-level debug "
    cmd+="--host localhost "
    cmd+="--user admin "
    cmd+="--password-url file:///config/cloud/openstack/adminPwd "
    cmd+="${vlan_params} "
    cmd+="${selfip_params} "
    cmd+="${gateway_opt} ${default_gateway} "
    eval "$cmd"
}

function disable_dhclient() {
    echo "Disabling dhclient for mgmt nic"
    tmsh modify sys db dhclient.mgmt { value disable }
    tmsh save sys config

}

function send_heat_signal() {
    onboardNetworkErrorCount=$(tail "$logFile" | grep "Network setup error" -i -c)

    if [ "$onboardNetworkErrorCount" -gt 0 ]; then
        msg="Onboard-network command exited with error. See $logFile for details."
    else
        onboardNetworkFailureCount=$(tail "$logFile" | grep "network setup failed" -i -c)
        if [ "$onboardNetworkFailureCount" -gt 0 ]; then
            msg="Onboard-network command exited with failure. See $logFile for details."
        else
            stat="SUCCESS"
            msg="Onboard-network command exited without error."
        fi
    fi

    echo "$msg"
    wc_notify --data-binary '{"status": "'"$stat"'", "reason":"'"$msg"'"}' --retry 5 --retry-max-time 300 --retry-delay 30
}

function main() {
    set_vars
    onboard_network_run
    disable_dhclient
    send_heat_signal
}

main