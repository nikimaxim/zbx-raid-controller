#!/bin/bash
#
#    .VERSION
#    0.1
#
#    .DESCRIPTION
#    Author: Nikitin Maksim
#    Github: https://github.com/nikimaxim/zbx-raid-controller.git
#    Note: Zabbix lld for Controller RAID
#
#    .TESTING
#    OS: CentOS 7 x64
#    Controller RAID: Intel Integrated RAID Module RMS25CB080, Intel RAID Controller RS2BL040
#

CLI='/opt/MegaRAID/MegaCli/MegaCli64'
PATH_CTRL_COUNT='/tmp/ctrl_count'

action=$1
part=$2


GetCtrlCount()
{
    ctrl_count=$($CLI -AdpCount -NoLog | grep -i "Controller Count:" | cut -f2 -d":" | sed -e 's/^\s*//' -e 's/\.//')
    /bin/echo ${ctrl_count} > ${PATH_CTRL_COUNT}
    /bin/echo ${ctrl_count}
}


CheckCtrlCount()
{
    if [ -f ${PATH_CTRL_COUNT} ]; then
        ctrl_count=$(/bin/cat ${PATH_CTRL_COUNT})
        if [ -z ${ctrl_count} ]; then
            ctrl_count=$(GetCtrlCount)
        fi
    else
        ctrl_count=$(GetCtrlCount)
    fi
    /bin/echo ${ctrl_count}
}


LLDControllers()
{
    ctrl_count=$(GetCtrlCount)
    ctrl_json=""
    
    for ctrl_id in $(seq 0 $((${ctrl_count} - 1))); do
        ctrl_id=$(echo ${ctrl_id} | tr -dc '[:print:]')
        ctrl_model="-" #$($CLI -AdpAllInfo -a${ctrl_id} -NoLog | grep -i "Product Name" | cut -f2 -d":" | sed -e 's/^\s*//')
        ctrl_sn=$($CLI -AdpAllInfo -a${ctrl_id} -NoLog | grep -i "Serial No" | cut -f2 -d":" | sed -e 's/^\s*//')
        ctrl_json=${ctrl_json}"{\"{#CTRL.ID}\":\"${ctrl_id}\",\"{#CTRL.MODEL}\":\"${ctrl_model}\",\"{#CTRL.SN}\":\"${ctrl_sn}\"},"
    done

    echo "{\"data\":[$(echo ${ctrl_json} | sed -e 's/,$//')]}"
}


LLDBattery()
{
    ctrl_count=$(CheckCtrlCount)
    bt_json=""

    for ctrl_id in $(seq 0 $((${ctrl_count} - 1))); do
        ctrl_bt=$($CLI -AdpBbuCmd -a${ctrl_id} -NoLog | grep -i "Battery State:" | cut -f2 -d":" | sed -e 's/^\s*//')
        if [ -n "${ctrl_bt}" ]; then
            bt_json=${bt_json}"{\"{#CTRL.ID}\":\"${ctrl_id}\",\"{#CTRL.BATTERY}\":\"${ctrl_id}\"},"
        fi
    done

    echo "{\"data\":[$(echo ${bt_json} | sed -e 's/,$//')]}"
}


LLDPhysicalDrives()
{
    ctrl_count=$(CheckCtrlCount)
    pd_json=""

    for ctrl_id in $(seq 0 $((${ctrl_count} - 1))); do
        pd_list=$($CLI -PDList -a${ctrl_id} -NoLog | grep -i "Slot Number" | cut -f2 -d":" | sed -e 's/^\s*//')
        ed_list=$($CLI -EncInfo -a${ctrl_id} -NoLog | grep -Eo "\s*Device ID\s*:\s*\w+$" | head -n1 | cut -f2 -d":" | tr -d '\r\n' | sed -e 's/^\s*//')
        for ed_id in ${ed_list}; do
            for pd_id in ${pd_list}; do
                pd_sn=$($CLI -PDInfo -PhysDrv[${ed_id}:${pd_id}] -a${ctrl_id} -NoLog | grep -i "Inquiry Data" | cut -f2 -d":" | sed "s/ \{2,10\}/ /g" | grep -Eo "(\d+|\w+)\s?$" | tr -d '\r\n' | sed -e 's/ $//')
                pd_json=${pd_json}"{\"{#CTRL.ID}\":\"${ctrl_id}\",\"{#ED.ID}\":\"${ed_id}\",\"{#PD.ID}\":\"${pd_id}\",\"{#PD.SN}\":\"${pd_sn}\"},"
            done
        done
    done
    
    echo "{\"data\":[$(echo ${pd_json} | sed -e 's/,$//')]}"
}


LLDLogicalDrives()
{
    ctrl_count=$(CheckCtrlCount)
    ld_json=""

    for ctrl_id in $(seq 0 $((${ctrl_count} - 1))); do
        ld_ids=$($CLI -LDInfo -LAll -a${ctrl_id} -NoLog | grep -i "(Target Id" | cut -f2 -d"(" | cut -f2 -d":" | sed -e 's/^\s*//' -e 's/)$//')
        for ld_id in $ld_ids; do
            ld_name=$($CLI -LDInfo -L${ld_id} -a${ctrl_id} -NoLog | grep -i "Name" | cut -f2 -d":" | sed -e 's/^\s*//')
            ld_raid=$($CLI -LDInfo -L${ld_id} -a${ctrl_id} -NoLog | grep -i "RAID Level" | cut -f2 -d":" | cut -f1 -d"," | sed -e 's/^\s*//')
            if [ -z "${ld_name}" ]; then
                ld_name=${ld_id}
            fi
            ld_json=${ld_json}"{\"{#CTRL.ID}\":\"${ctrl_id}\",\"{#LD.ID}\":\"${ld_id}\",\"{#LD.NAME}\":\"${ld_name}\",\"{#LD.RAID}\":\"${ld_raid}\"},"
        done
    done

    echo "{\"data\":[$(echo ${ld_json} | sed -e 's/,$//')]}"
}


GetControllerStatus()
{
    ctrl_id=$1
    ctrl_part=$2
    value=""
    
    case ${ctrl_part} in
#        "main")
#            value=$()
#        ;;
        "battery")
            value=$($CLI -AdpBbuCmd -a${ctrl_id} -NoLog | grep -i "Battery State:" | cut -f2 -d":" | sed -e 's/^\s*//')
        ;;
        "temperature")
            value=$($CLI -AdpAllInfo -a${ctrl_id} -NoLog | grep -i "ROC temperature" | cut -f2 -d":" | cut -f2 -d" " | tr -d '\r\n' | sed -e 's/^\s*//')
        ;;
    esac
    
    echo ${value}
}


GetPhysicalDriveStatus()
{
    ctrl_id=$1
    pd_id=$2
    ed_id=$3
    
    echo $($CLI -PDInfo -PhysDrv[${ed_id}:${pd_id}] -a${ctrl_id} -NoLog | grep -i "Firmware state:" | cut -f2 -d":" | cut -f1 -d"," | sed -e 's/^\s*//')
}


GetLogicalDriveStatus()
{
    ctrl_id=$1
    ld_id=$2

    echo $($CLI -LDInfo -L${ld_id} -a${ctrl_id} -NoLog | grep -i "State" | cut -f2 -d":" | sed -e 's/^\s*//')
}


case ${action} in
    "lld")
        case ${part} in
            "ad")
                LLDControllers
            ;;
            "bt")
                LLDBattery
            ;;
            "pd")
                LLDPhysicalDrives
            ;;
            "ld")
                LLDLogicalDrives
            ;;
        esac
    ;;
    "health")
        case ${part} in
            "ad")
                GetControllerStatus $3 $4
            ;;
            "pd")
                GetPhysicalDriveStatus $3 $4 $5
            ;;
            "ld")
                GetLogicalDriveStatus $3 $4
            ;;
        esac
    ;;
esac
