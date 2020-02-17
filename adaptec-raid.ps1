<#
    .VERSION
    0.3

    .DESCRIPTION
    Author: Nikitin Maksim
    Github: https://github.com/nikimaxim/zbx-raid-controller.git
    Note: Zabbix lld for RAID Controller

    .TESTING
    OS: Windows 2008R2 x64
    PowerShell: 5.1 and later
    Controller RAID: ASR8405, ASR-8405E, Adaptec 6805, Adaptec 6405E
 #>

Param (
    [ValidateSet("lld","health")][Parameter(Position=0, Mandatory=$True)][string]$action,
    [ValidateSet("ad","ld","pd","bt")][Parameter(Position=1, Mandatory=$True)][string]$part,
    [string][Parameter(Position=2)]$ctrlid,
    [string][Parameter(Position=3)]$partid
)

$CLI = "C:\service\StorMan\arcconf.exe"
$PATH_CTRL_COUNT = "C:\Windows\Temp\ctrl_count"


function GetCtrlCount() {
    $ctrl_count = ((& $CLI "LIST".Split() | Where-Object {$_ -match "Controllers found"}) -split ':')[1].Trim() | Tee-Object $PATH_CTRL_COUNT
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

    for($ctrl_id = 1; $ctrl_id -le $ctrl_count; $ctrl_id++) {
        $response = (((& $CLI "LIST".Split() | Where-Object {$_ -match "Controller $ctrl_id"}) -split ' :')[1] -split ',')
        $ctrl_model = "-" #$response[3].Trim()
        $ctrl_sn = $response[4].Trim()

        $ctrl_json += [string]::Format('{{"{{#CTRL.ID}}":"{0}","{{#CTRL.MODEL}}":"{1}","{{#CTRL.SN}}":"{2}"}},',$ctrl_id, $ctrl_model, $ctrl_sn)
    }

    return '{"data":[' + $($ctrl_json -replace ',$') + ']}'
}


function LLDBattery() {
    $ctrl_count = CheckCtrlCount
    $bt_json = ""

    for($i = 1; $i -le $ctrl_count; $i++) {
        $response = ((& $CLI GETCONFIG $i AD | Select-String "Controller Battery Information" -Context 0,2 | Select-String -InputObject {$_.Context.PostContext} -Pattern "Status") -split ':')
        if($response) {
            $bt_status = $response[1].Trim()
            if($bt_status -ne "Not Installed") {
                $bt_json += [string]::Format('{{"{{#CTRL.ID}}":"{0}","{{#CTRL.BATTERY}}":"{1}"}},', $i, $i)
            }
        }
    }

    return '{"data":[' + $($bt_json -replace ',$') + ']}'
}


function LLDPhysicalDrives() {
    $ctrl_count = CheckCtrlCount
    $pd_json = ""

    for($ctrl_id = 1; $ctrl_id -le $ctrl_count; $ctrl_id++) {
        [array]$response = & $CLI "GETCONFIG $ctrl_id PD".Split() | Where-Object {$_ -match "Device\s[#]\d+|Device is |Serial number"}

        for($j = 0; $j -lt $response.Length;) {
            if(!($response[$j+1] -match "Enclosure Services Device")) {
                $pd_id = ($response[$j] -replace "Device #").Trim()
                $pd_sn = ($response[$j + 2] -split ':')[1].Trim()
                $pd_json += [string]::Format('{{"{{#CTRL.ID}}":"{0}","{{#PD.ID}}":"{1}","{{#PD.SN}}":"{2}"}},', $ctrl_id, $pd_id, $pd_sn)
            }
            $j += 3
        }
    }

    return '{"data":[' + $($pd_json -replace ',$') + ']}'
}


function LLDLogicalDrives() {
    $ctrl_count = CheckCtrlCount
    $ld_json = ""

    for($ctrl_id = 1; $ctrl_id -le $ctrl_count; $ctrl_id++) {
        $response = (& $CLI "GETCONFIG $ctrl_id AD".Split() | Where-Object {$_ -match "Logical devices/Failed/Degraded"}) -match '[:\s](\d+)'
        $ld_count = $Matches[1]

        for($ld_id = 0; $ld_id -lt $ld_count; $ld_id++) {
            [array]$response = & $CLI "GETCONFIG $ctrl_id LD $ld_id".Split() | Where-Object {$_ -match "Logical device name|RAID level"}

            $ld_name = ($response[0] -split ':')[1].Trim()
            $ld_raid = ($response[1] -split ':')[1].Trim()

            if($ld_name -eq "") {
                $ld_name = $ld_id
            }

            $ld_json += [string]::Format('{{"{{#CTRL.ID}}":"{0}","{{#LD.ID}}":"{1}","{{#LD.NAME}}":"{2}","{{#LD.RAID}}":"{3}"}},', $ctrl_id, $ld_id, $ld_name, $ld_raid)
        }
    }

    return '{"data":[' + $($ld_json -replace ',$') + ']}'
}


function GetControllerStatus() {
    Param (
        [ValidateSet("main","battery","temperature")][string]$ctrl_part
    )

    $value = ""

    switch($ctrl_part) {
        "main" {
            $response = ((& $CLI "LIST".Split() |  Where-Object {$_ -match "Controller $ctrlid"}) -split ' :')[1] -split ','
            if ($response) {
                $value = $response[0].Trim()
            }
        }
        "battery" {
            $bt_status = ((& $CLI "GETCONFIG $ctrlid AD" | Select-String "Controller Battery Information" -Context 0,2 | Select-String -InputObject {$_.Context.PostContext} -Pattern "Status") -split ':')
            if($bt_status) {
                $value = $bt_status[1].Trim()
            }
        }
        "temperature" {
            $response = (& $CLI "GETCONFIG $ctrlid AD".Split() | Where-Object {$_ -match "^\s+Temperature\s+[:]"}) -match '(\d+).*[C]'
            if($response) {
                $value = $Matches[1]
            }
        }
    }

    return $value
}


function GetPhysicalDriveStatus() {
    [array]$response = & $CLI "GETCONFIG $ctrlid PD".Split() | Where-Object {$_ -match "^\s+State\s+[:] "}
    return ($response[$partid] -split ':')[1].Trim()
}


function GetLogicalDriveStatus() {
    $response = & $CLI "GETCONFIG $ctrlid LD $partid".Split() | Where-Object {$_ -match "Status of logical device"}
    return ($response -split ':')[1].Trim()
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
