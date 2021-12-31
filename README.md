# SAP on Azure AppServers AvZone Switchover
## Overview ##

For SAP deployments on Azure using Availability zones, one of the architecture patterns is to have SAP application servers in Active/Passive mode as shown below. In an Active/Passive setup when database fails over from Zone 1 to Zone 2 in the picture below, SAP application servers need to switchover as well. This solution provides framework and code to facilitate this switchover in an automated way using Automation runbook and Pacemaker Alert agent. 

![avzone architecture](images/avzone_architecture.jpg)


## Pre-Requisites

-- You have an SAP application deployed across Availability Zones in Active/Passive setup as described [here](https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/sap-ha-availability-zones#activepassive-deployment)