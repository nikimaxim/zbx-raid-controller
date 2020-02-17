## Zabbix monitoring RAID Controller
- https://github.com/nikimaxim/zbx-raid-controller.git

### Windows Install 
#### Requirements:
- OS: Windows 7, 2008R2 and later
- PowerShell: 2.0 and later
- Zabbix-agent: 4.0 and later
- Arcconf: 2.6 and later(Adaptec)
- MegaCli(CMDTool2): 8.7.14 and later(Lsi)

#### Get Utils arcconf(Adaptec)
- adaptec.com

#### Get Utils MegaCli(Lsi)
- intel.com

#### Check correct versions PowerShell: (Execute in PowerShell!) (Requirements!)
- Get-Host|Select-Object Version

#### Copy powershell script:
##### For Adaptec
- **github**/adaptec-raid.ps1 in C:\service\zabbix_agent\adaptec-raid.ps1
##### For Lsi !!!(In developing)!!!
- **github**/lsi-raid.ps1 in C:\service\zabbix_agent\lsi-raid.ps1

#### Check powershell script(Out json): (CMD!)
##### For Adaptec
- powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File "C:\service\zabbix_agent\adaptec-raid.ps1" lld ad
##### For Lsi
- powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File "C:\service\zabbix_agent\lsi-raid.ps1" lld ad

#### Add from zabbix_agentd.conf "UserParameter" in zabbix_agentd.conf zabbix_agent:
- **github**/zabbix_agentd.conf

#### Import zabbix template:
##### For Adaptec
- **github**/Template Adaptec RAID Controller.xml
##### For Lsi
- **github**/Template Lsi RAID Controller.xml

<br/>

### Linux Install 
#### Requirements:
- OS: RedHat family
- Zabbix-agent: 4.0 and later
- Arcconf: 2.6 and later(Adaptec)
- MegaCli: 8.7 and later(Lsi)

#### Get Utils arcconf(Adaptec)
- adaptec.com

#### Get Utils MegaCli(Lsi)
- intel.com

#### Copy bash script:
##### For Adaptec
- **github**/adaptec-raid.sh in /opt/zabbix_s/adaptec-raid.sh
##### For Lsi
- **github**/lsi-raid.sh in /opt/zabbix_s/lsi-raid.sh

#### Chmod and Chown
- chmod -R 750 /opt/zabbix_s/
- chown -R root:zabbix /opt/zabbix_s/

#### Check bash script(Out json):
- /opt/zabbix_s/adaptec-raid.sh lld ad

#### Add from zabbix_agentd.conf "UserParameter" in zabbix_agentd.conf zabbix_agent:
- **github**/zabbix_agentd.conf

#### Add in /etc/sudoers
##### For Adaptec script
zabbix  ALL=(root) NOPASSWD: /opt/zabbix_s/adaptec-raid.sh
##### For Lsi script
zabbix ALL=(root) NOPASSWD: /opt/zabbix_s/lsi-raid.sh

#### Import zabbix template:
##### For Adaptec
- **github**/Template Adaptec RAID Controller.xml
##### For Lsi
- **github**/Template Lsi RAID Controller.xml

<br/>

#### Examples images:
- Graph: Temperature RAID Controller
![Image alt](https://github.com/nikimaxim/zbx-raid-controller/blob/master/img/3.png)

<br/>

- Discovery rules

<br/>

![Image alt](https://github.com/nikimaxim/zbx-raid-controller/blob/master/img/1.png)

<br/>

- Items prototypes

<br/>

![Image alt](https://github.com/nikimaxim/zbx-raid-controller/blob/master/img/2.png)

<br/>

- Latest data

<br/>

![Image alt](https://github.com/nikimaxim/zbx-raid-controller/blob/master/img/4.png)

<br/>

#### License
- GPL v3
