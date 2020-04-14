<#
    .VERSION
    0.2

    .DESCRIPTION
    Author: Nikitin Maksim
    Github: https://github.com/nikimaxim/zbx-raid-controller.git
    Note: Zabbix lld for RAID Controller

    .TESTING
    OS: Windows 2008R2 x64
    PowerShell: 5.1 and later
    Controller RAID: Intel Integrated RAID Module RMS25CB080, Intel RAID Controller RS2BL040, LSI MegaRAID SAS 9240-4i
 #>

Param (
    [ValidateSet("lld","health")][Parameter(Position=0, Mandatory=$True)][string]$action,
    [ValidateSet("ad","ld","pd","bt")][Parameter(Position=1, Mandatory=$True)][string]$part,
    [string][Parameter(Position=2)]$ctrlid,
    [string][Parameter(Position=3)]$partid,
    [string][Parameter(Position=4)]$edid
)

$CLI = "C:\service\MegaRAID\MegaCli\MegaCli64.exe"
$PATH_CTRL_COUNT = "C:\Windows\Temp\ctrl_count"


if ((Get-Command $CLI -ErrorAction SilentlyContinue) -eq $null) {
    Write-Host "Could not find path: $CLI"
    exit
}

function GetCtrlCount() {
    $ctrl_count = ((& $CLI "-AdpCount -NoLog".Split() | Where-Object {$_ -match "Controller Count:"}) -split ':')[1].Trim(' .') | Tee-Object $PATH_CTRL_COUNT
    return $ctrl_count
}


function CheckCtrlCount() {
    if (Test-path $PATH_CTRL_COUNT) {
        $ctrl_count = Get-Content $PATH_CTRL_COUNT
        if (!$ctrl_count) {
            return GetCtrlCount
        }
    } else {
        return GetCtrlCount
    }

    return $ctrl_count
}


function LLDControllers() {
    $ctrl_count = GetCtrlCount
    $ctrl_json = ""

    for ($ctrl_id = 0; $ctrl_id -lt $ctrl_count; $ctrl_id++) {
        $response = & $CLI "-AdpAllInfo -a $ctrl_id -NoLog".Split()
        $ctrl_model = (($response | Where-Object {$_ -match "Product Name"}) -split ':')[1].Trim()
        $ctrl_sn = (($response | Where-Object {$_ -match "Serial No"}) -split ':')[1].Trim()

        $ctrl_json += [string]::Format('{{"{{#CTRL.ID}}":"{0}","{{#CTRL.MODEL}}":"{1}","{{#CTRL.SN}}":"{2}"}},',$ctrl_id, $ctrl_model, $ctrl_sn)
    }

    return '{"data":[' + $($ctrl_json -replace ',$') + ']}'
}


function LLDBattery() {
    $ctrl_count = CheckCtrlCount
    $bt_json = ""

    for ($i = 0; $i -lt $ctrl_count; $i++) {
        $response = & $CLI "-AdpBbuCmd -a $ctrl_id -NoLog".Split()
        $bt_status = $response | Where-Object {$_ -match "Battery State:"}
        if ($bt_status) {
            $bt_sn_temp = $response | Where-Object { $_ -match "Serial Number:" }
            if ($bt_sn_temp) {
                $bt_sn = ($bt_sn_temp -split ':')[1].Trim()
            } else {
                $bt_sn = "-"
            }

            $bt_json += [string]::Format('{{"{{#CTRL.ID}}":"{0}","{{#CTRL.BATTERY}}":"{1}","{{#CTRL.BATTERY.SN}}":"{2}"}},', $i, 0, $bt_sn)
        }
    }

    return '{"data":[' + $($bt_json -replace ',$') + ']}'
}


function LLDPhysicalDrives() {
    $ctrl_count = CheckCtrlCount
    $pd_json = ""

    for ($ctrl_id = 0; $ctrl_id -lt $ctrl_count; $ctrl_id++) {
        $pd_count = ((& $CLI "-PDGetNum -a $ctrl_id -NoLog".Split() | Where-Object {$_ -match "Number of Physical Drives on Adapter"}) -split ':')[1].Trim()
        $ed_ids = ((& $CLI "-EncInfo -a $ctrl_id -NoLog".Split() | Where-Object {$_ -match "\s*Device ID"}) -split ':')[1].Trim()
        foreach ($ed_id in $ed_ids) {
            for ($pd_id = 0; $pd_id -lt $pd_count; $pd_id++) {
                $pd_sn = (((& $CLI "-PDInfo -PhysDrv[$($ed_id):$($pd_id)] -a $ctrl_id -NoLog".Split() | Where-Object {$_ -match "Inquiry Data" }) -split ':')[1]).Trim()
                if ($pd_sn) {
                    $pd_json += [string]::Format('{{"{{#CTRL.ID}}":"{0}","{{#ED.ID}}":"{1}","{{#PD.ID}}":"{2}","{{#PD.SN}}":"{3}"}},', $ctrl_id, $ed_id, $pd_id, $pd_sn.Split()[1].Trim())
                }
            }
        }
    }

    return '{"data":[' + $($pd_json -replace ',$') + ']}'
}


function LLDLogicalDrives() {
    $ctrl_count = CheckCtrlCount
    $ld_json = ""

    for ($ctrl_id = 0; $ctrl_id -lt $ctrl_count; $ctrl_id++) {
        $ld_count = (((& $CLI "-LDGetNum -a $ctrl_id -NoLog".Split() | Where-Object {$_ -match "Number of Virtual Drives Configured on Adapter"}) -split ':')[1]).Trim()
        for ($ld_id = 0; $ld_id -lt $ld_count; $ld_id++) {
            $response = & $CLI "-LDInfo -LAll -a $ctrl_id -NoLog".Split()
            $ld_name = (($response | Where-Object {$_ -match "Name"}) -split ':')[1].Trim()
            $ld_raid = ((($response | Where-Object {$_ -match "RAID Level"}) -split ':')[1] -split ",")[0].Trim()

            if ($ld_name -eq "") {
                $ld_name = $ld_id
            }

            $ld_json += [string]::Format('{{"{{#CTRL.ID}}":"{0}","{{#LD.ID}}":"{1}","{{#LD.NAME}}":"{2}","{{#LD.RAID}}":"{3}"}},', $ctrl_id, $ld_id, $ld_name, $ld_raid)
        }
    }

    return '{"data":[' + $($ld_json -replace ',$') + ']}'
}


function GetControllerStatus() {
    Param (
        [ValidateSet("main","temperature","battery","temperature_bt")][string]$ctrl_part
    )

    switch($ctrl_part) {
        #"main" {
        #    $response =
        #}
        "temperature" {
            $response = (& $CLI "-AdpAllInfo -a $ctrlid -NoLog".Split() | Where-Object {$_ -match "ROC temperature"})
            if ($response) {
                $temperature = ($response -split ':')[1]
                if ($temperature) {
                    $value = $temperature.Trim()
                }
            } else {
                Write-Host "Data not found"
            }
        }
        "battery" {
            $response = (& $CLI "-AdpBbuCmd -a $ctrlid -NoLog".Split() | Where-Object {$_ -match "Battery State:"})
            if ($response) {
                $bt_status = ($response -split ':')[1]
                if ($bt_status) {
                    $value = $bt_status.Trim()
                }
            } else {
                Write-Host "Data not found"
            }
        }
        "temperature_bt" {
            $response = (& $CLI "-AdpBbuCmd -a $ctrlid -NoLog".Split() | Where-Object {$_ -match "Temperature:"})
            if ($response) {
                $temperature = ($response -split ':')[1]
                if ($temperature) {
                    $value = $temperature.TrimEnd("C").Trim()
                }
            } else {
                Write-Host "Data not found"
            }
        }
    }

    return $value
}


function GetPhysicalDriveStatus() {
    $response = (& $CLI "-PDInfo -PhysDrv[$($edid):$($partid)] -a $ctrlid -NoLog".Split() | Where-Object {$_ -match "Firmware state:"})

    if ($response) {
        return ((($response -split ':')[1]) -split ',')[0].Trim()
    } else {
        Write-Host "Data not found"
    }
}


function GetLogicalDriveStatus() {
    $response = (& $CLI "-LDInfo -L $partid -a $ctrlid -NoLog".Split() | Where-Object {$_ -match "State"})

    if ($response) {
        return ($response -split ':')[1].Trim()
    } else {
        Write-Host "Data not found"
    }
}


switch($action) {
    "lld" {
        switch($part) {
            "ad" {LLDControllers}
            "bt" {LLDBattery}
            "pd" {LLDPhysicalDrives}
            "ld" {LLDLogicalDrives}
        }
    }
    "health" {
        switch($part) {
            "ad" {GetControllerStatus -ctrl_part $partid}
            "pd" {GetPhysicalDriveStatus}
            "ld" {GetLogicalDriveStatus}
        }
    }
}
