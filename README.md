# SAP on Azure AppServers AvZone Switchover
## Overview ##

For SAP deployments on Azure using Availability zones, one of the architecture patterns is to have SAP application servers in Active/Passive mode as shown below. In an Active/Passive setup when database fails over from Zone 1 to Zone 2 in the picture below, SAP application servers need to switchover as well. This solution provides approach and code to facilitate this switchover in an automated way using Automation runbooks and Pacemaker Alert agent. 

![avzone architecture](images/avzone_architecture.jpg)


## Pre-Requisites
- You have an SAP application deployed across Availability Zones in Active/Passive setup as described [here](https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/sap-ha-availability-zones#activepassive-deployment)
- SAP Database tier is running on Linux with HA configured across Availability Zones using Pacemaker. If database tier is on Windows 
- Zone which hosts the passive node of the database has equal number of SAP application servers (as active Zone) built, configured (logon groups, batch groups, message server ACLs etc.) and shutdown. 
- The runbook leverages the [SAP Start Stop Automation Framework](https://github.com/Azure/SAP-on-Azure-Scripts-and-Utilities/tree/main/Start-Stop-Automation/Automation-Backend). Hence all Application servers need to have 3 mandatory tags mentioned below 
    | Tag | Explanation |
   | --- | --- |
  | SAPSystemSID | SID of SAP application | 
  | SAPApplicationInstanceType  | SAP_D (which signifies Dialog instances) |
  | SAPApplicationInstanceNumber | Instance number of SAP app server |

- Azure VM Name and hostname need to be identical. If these are different modify the runbooks accordingly.
- Code assumes that the database SID and application server SID are identical. If these are different modify the runbooks accordingly.  

## Code Walkthrough

***runbook-trigger.sh*** 
- This shell script will be used by the Alert agent of the Pacemaker cluster.  
- The script checks if the alert task is for a database node being **Promoted**. If this is the case it calls the **webhook** of an Azure automation runbook passing values of Promoted VM, Demoted VM, SAP database SID. If not no action is taken

***Switch-SAPApplicationServers.ps1***
- This runbook takes the following parameters as inputs

| Parameter | Explanation |
| --- | --- |
| WebhookData | JSON with details of the switchover alert. Sample JSON {"ClusterType":"HANA","SAPSystemId":"ABC","PromotedNode":"xxxxxx","DemotedNode":"xxxxxx"} |
| automationaccount |  Specifies the automation account which hosts this runbook as well as Start-SAPApplicationServer and Stop-SAPApplicationServer runbooks |
| automationRG | Specifies the resource group of the automation account |
| runbookName | Specifies the name of this runbook. Used to check job concurrency |
| SAPApplicationServerWaitTime | Time to wait in Seconds when starting the SAP application Servers |
| SAPSoftShutdownTimeInSeconds | Softshutdown timeout used for stopping SAP application servers on the passive Zone |
| jobMaxRuntimeInSeconds | Max runtime for the job in seconds. |

- The runbook initially fetches the Zone details of Promoted and Demoted database VMs using the Get-AzVM command. 
- Once we have the Zone details, we then collect all SAP application servers for the particular SID using the Tags and segregate them to Zones. 
-  We first need to start all application servers on the newly Promoted AvZone. This is done by calling runbook Start-SAPApplicationServer.ps1 as child jobs for each of the application server.  Child jobs are all started in Parallel. 
-  We now wait for all jobs to come to a Terminal state. If all jobs Complete successfully we move to the next step. If any of the job fails we exit. 
-  Next step is to stop application servers on the newly Demoted AvZone. This is done by calling runbook Stop-SAPApplicationServer.ps1 using child jobs similar to above. 

## Implementation Steps
- 