#!/bin/bash
#
#    .VERSION
#    0.4
#
#    .DESCRIPTION
#    Author: Nikitin Maksim
#    Github: https://github.com/nikimaxim/zbx-raid-controller.git
#    Note: Zabbix lld for Controller RAID
#
#    .TESTING
#    OS: CentOS 7 x64
#    Controller RAID: ASR8405, ASR-8405E, Adaptec 6805, Adaptec 6405E, Adaptec 5805
#

CLI='/opt/StorMan/arcconf'
PATH_CTRL_COUNT='/tmp/ctrl_count'

action=$1
part=$2


if [ ! -f ${CLI} ]; then
    echo "Could not find path: ${CLI}"
    exit
fi

GetCtrlCount() {
    ctrl_count=$($CLI LIST | grep -i "Controllers found:" | cut -f2 -d":" | sed -e 's/^\s*//')
    echo ${ctrl_count} > ${PATH_CTRL_COUNT}
    echo ${ctrl_count}
}


CheckCtrlCount() {
    if [ -f ${PATH_CTRL_COUNT} ]; then
        ctrl_count=$(cat ${PATH_CTRL_COUNT})
        if [ -z ${ctrl_count} ]; then
            ctrl_count=$(GetCtrlCount)
        fi
    else
        ctrl_count=$(GetCtrlCount)
    fi
    echo ${ctrl_count}
}


LLDControllers() {
    ctrl_count=$(GetCtrlCount)
    ctrl_json=""

    for ctrl_id in $(seq 1 ${ctrl_count}); do
        response=$($CLI LIST | grep "Controller ${ctrl_id}" | cut -f3 -d":")
        ctrl_model="-" #$(/bin/echo $response | awk -F "," '{print $4}' | sed -e 's/^\s*//')
        ctrl_sn=$(/bin/echo $response | awk -F "," '{print $5}' | sed -e 's/^\s*//')
        ctrl_json=${ctrl_json}"{\"{#CTRL.ID}\":\"${ctrl_id}\",\"{#CTRL.MODEL}\":\"${ctrl_model}\",\"{#CTRL.SN}\":\"$ctrl_sn\"},"
    done

    echo "{\"data\":[$(echo ${ctrl_json} | sed -e 's/,$//')]}"
}


LLDBattery() {
    ctrl_count=$(CheckCtrlCount)
    bt_json=""

    for ctrl_id in $(seq 1 ${ctrl_count}); do
        ctrl_bt=$($CLI GETCONFIG ${ctrl_id} AD | grep -i -A 2 "^\s*Controller Battery Information" | grep -iE "^\s+Status\s+[:]" | cut -f2 -d":" | sed -e 's/^ //' | grep -iEv "\w*\s*[Not]+\s*installed")
        if [ -n "${ctrt_bt}" ]; then
            bt_json=${bt_json}"{\"{#CTRL.ID}\":\"${ctrl_id}\"},"
        fi
    done

    echo "{\"data\":[$(echo ${bt_json} | sed -e 's/,$//')]}"
}


LLDPhysicalDrives() {
    ctrl_count=$(CheckCtrlCount)
    pd_json=""
    
    for ctrl_id in $(seq 1 ${ctrl_count}); do
        IFS=$'\n'
        response=($($CLI GETCONFIG ${ctrl_id} PD | grep -e "Device #" -e "Device is" -e "Serial number"))
        i=0
        while [ $i -lt ${#response[@]} ]; do
            pd_type=$(echo ${response[$((${i}+1))]} | cut -f2 -d":" | sed -e 's/^\s*//' -e 's/ /_/g')
            if [[ ! ${pd_type} =~ "Enclosure_Services_Device" ]]; then
                pd_id=$(echo ${response[${i}]} | cut -f2 -d"#")
                pd_sn=$(echo ${response[$((${i}+2))]} | cut -f2 -d":" | sed -e 's/^\s*//')
                if [ ${#pd_sn} -gt 0 ]; then
                    pd_json=${pd_json}"{\"{#CTRL.ID}\":\"${ctrl_id}\",\"{#PD.ID}\":\"${pd_id}\",\"{#PD.SN}\":\"${pd_sn}\"},"
                fi
                i=$(($i+3))
            else
                if [[ $(echo ${response[$((${i}+2))]}) =~ "Serial number" ]]; then
                    i=$(($i+3))
                else
                    i=$(($i+2))
                fi
            fi
        done
    done

    echo "{\"data\":[$(echo ${pd_json} | sed -e 's/,$//')]}"
}


LLDLogicalDrives() {
    ctrl_count=$(CheckCtrlCount)
    ld_json=""

    for ctrl_id in $(seq 1 ${ctrl_count}); do
        ld_ids=$($CLI GETCONFIG ${ctrl_id} LD | grep -i "Logical device number " | cut -f4 -d" " | sed -e 's/^\s*//')
        for ld_id in ${ld_ids}; do
            ld_name=$($CLI GETCONFIG ${ctrl_id} LD ${ld_id} | grep -i "Logical device name" | cut -f2 -d":" | sed -e 's/^\s*//')
            ld_raid=$($CLI GETCONFIG ${ctrl_id} LD ${ld_id} | grep -i "RAID level" | cut -f2 -d":" | sed -e 's/^\s*//')
            if [ -z "${ld_name}" ]; then
                ld_name=${ld_id}
            fi
            ld_json=$ld_json"{\"{#CTRL.ID}\":\"${ctrl_id}\",\"{#LD.ID}\":\"${ld_id}\",\"{#LD.NAME}\":\"${ld_name}\",\"{#LD.RAID}\":\"${ld_raid}\"},"
        done
    done

    echo "{\"data\":[$(echo ${ld_json} | sed -e 's/,$//')]}"
}


GetControllerStatus() {
    ctrl_id=$1
    ctrl_part=$2
    value=""
    
    case ${ctrl_part} in
        "main")
            value=$($CLI LIST | grep "Controller ${ctrl_id}" | cut -f3 -d":" | awk -F "," '{print $1}' | sed -e 's/^\s*//')
        ;;
        "temperature")
            value=$($CLI GETCONFIG ${ctrl_id} AD | grep -iE "^\s+Temperature\s+[:]" | cut -f2 -d":" | awk '{print $1}')
        ;;
        "battery")
            value=$($CLI GETCONFIG ${ctrl_id} AD | grep -i -A 2 "^\s*Controller Battery Information" | grep -iE "^\s+Status\s+[:]" | cut -f2 -d":" | sed -e 's/^\s*//')
        ;;
    esac

    echo ${value}
}


GetPhysicalDriveStatus() {
    ctrl_id=$1
    pd_id=$2
    response=$($CLI GETCONFIG ${ctrl_id} PD 0 ${pd_id} | grep -ioP "^\s+State.*$" | cut -f2 -d":" | sed -E 's/[ ]//g')

    if [ -n ${response} ]; then
        echo ${response}
    else
        echo "Data not found"
    fi
}


GetLogicalDriveStatus() {
    ctrl_id=$1
    ld_id=$2
    response=$($CLI GETCONFIG ${ctrl_id} LD $ld_id | grep -i "Status of logical device" | cut -f2 -d":" | sed -e 's/^\s*//')

    if [ -n ${response} ]; then
        echo ${response}
    else
        echo "Data not found"
    fi
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
                GetPhysicalDriveStatus $3 $4
            ;;
            "ld")
                GetLogicalDriveStatus $3 $4
            ;;
        esac
    ;;
esac
