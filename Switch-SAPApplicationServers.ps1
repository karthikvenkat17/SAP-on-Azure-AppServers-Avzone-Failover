<#
.SYNOPSIS
   Used to switch SAP application servers from passive Zone to active Zone with respect to SAP database in an Active/Passive setup.  

.DESCRIPTION
    Runbook Starts SAP app servers in the same zone as Promoted Node of the database and stops SAP app servers in the Zone where 
    passive node of the database is located. Runbook can be triggered by a webhook from Pacemaker cluster,   

.PARAMETER WebhookData
    JSON with details of the switchover. Sample JSON shown below
    {"ClusterType":"HANA","SAPSystemId":"ABC","PromotedNode":"xxxxxx","DemotedNode":"xxxxxx"}

.PARAMETER automationAccount
    Specifies the automation account which hosts this runbook as well as Start-SAPApplicationServer and Stop-SAPApplicationServer runbooks

.PARAMETER automationRG
    Specifies the resource group of the automation account 

.PARAMETER runbookName
    Specifies the name of this runbook. Used to check job concurrency

.PARAMETER SAPApplicationServerWaitTime
    Time to wait in Seconds when starting the SAP application Servers.

.PARAMETER SAPSoftShutdownTimeInSeconds
    Softshutdown timeout used for stopping SAP application servers on the passive Zone

.PARAMETER jobMaxRuntimeInSeconds
    Max runtime for the job in seconds
  
.NOTES
    Author: Karthik Venkatraman
#>

param(
    [Parameter(Mandatory = $true)]
    [object]$WebhookData,
    [Parameter(Mandatory = $true)]
    [String]$automationAccount,
    [Parameter(Mandatory = $true)]
    [String]$automationRG,
    [Parameter(Mandatory = $true)]
    [String]$runbookName,
    [Parameter(Mandatory = $true)]
    [Int32]$SAPApplicationServerWaitTime = 300,
    [Parameter(Mandatory = $true)]
    [Int32]$SAPSoftShutdownTimeInSeconds = 300,
    [Parameter(Mandatory = $true)]
    [Int32]$jobMaxRuntimeInSeconds = 7200
)


#Set-PSDebug -Trace 2

function Get-TimeStamp {    
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}
function Get-SAPAppInfoByZones {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory= $true)]
        [ValidateNotNullOrEmpty()]
        [String]$promotedZone,
        [Parameter(Mandatory= $true)]
        [ValidateNotNullOrEmpty()]
        [String]$demotedZone,
        [Parameter(Mandatory= $true)]
        [ValidateNotNullOrEmpty()]
        [String]$sapSID
    )
    BEGIN {}
    PROCESS {
        try {
            #Write-Output "Fetching the application server list for $sapSID"
            $tags = @{"SAPSystemSID" = $sapSID }
            $appVMlist = Get-AzResource -ResourceType "Microsoft.Compute/virtualMachines"  -Tag $tags | `
                                            Where-Object { ($_.Tags.Item("SAPApplicationInstanceType") -EQ 'SAP_D') `
                                                    -or ($_.Tags.Item("SAPApplicationInstanceType") -EQ 'SAP_DVEBMGS') }         
            foreach ($appVM in $appVMlist) {
            $vmInfo =  Get-AzVM -Name $appvm.Name -ResourceGroupName $appVM.ResourceGroupName
            if ($vmInfo.Zones -eq $promotedZone) {
                $promotedZoneAppServers += @([PSCustomObject]@{
                    appVMName = $vmInfo.Name;
                    appVMRGName = $vmInfo.ResourceGroupName;
                    appZone = $vmInfo.Zones
                })
                }
               elseif ($vmInfo.Zones -eq $demotedZone){
                $demotedZoneAppServers += @([PSCustomObject]@{
                    appVMName = $vmInfo.Name;
                    appVMRGName = $vmInfo.ResourceGroupName;
                    appZone = $vmInfo.Zones
                })
                }
                else {
                    Write-Output "Application server $($vmInfo.Name) is in the zone different to the database VMs"
                }
                 
            }
            return $promotedZoneAppServers,$demotedZoneAppServers
            
    }
    catch {
        Write-Output  $_.Exception.Message
        Write-Output "AvZone information for the application servers cannot be found"
        exit 1
    }    
    }
    END {}

}

function Get-SAPAutomationJobStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$jobList,
        [Parameter(Mandatory = $true)]
        [String]$automationRG,
        [Parameter(Mandatory = $true)]
        [String]$automationAccount
    )
    BEGIN {}
    PROCESS {
        try {
            $PollingSeconds = 5
            $WaitTime = 0
            foreach ($job in $jobList) {
                $jobDetail = Get-AzAutomationJob -Id $job.JobID -ResourceGroupName $automationRG -AutomationAccountName $automationAccount
                while(-NOT (IsJobTerminalState $jobDetail.Status) -and $WaitTime -lt $jobMaxRuntimeInSeconds) {
                    Write-Information "Waiting for job $($jobDetail.JobID) to complete"
                    Start-Sleep -Seconds $PollingSeconds
                    $WaitTime += $PollingSeconds
                    $jobDetail = $jobDetail | Get-AzAutomationJob
                 }
                if ($jobDetail.Status -eq "Completed") {
                    $job.Status = "Success"
                    Write-Information "Job $($jobDetail.JobID) successfully completed"
                    }
                    else{
                    $job.Status = "NotSuccess"
                    Write-Information "Job $($jobDetail.JobID) didnt finish successfully. Check child runbook for errors"
                    }          
                }
            $failedJobs = $jobList | Where-Object {$_.Status -eq "NotSuccess"}
                if ($failedJobs.count -gt 0){
                    Write-Output "$(Get-TimeStamp) Some of the jobs failed. AvZone switch could not be completed successfully"
                    Write-Output $jobList
                    exit 1
                }
                else {
                return $jobList
                }
        }
        catch {
            Write-Output  $_.Exception.Message
            Write-Output "$(Get-TimeStamp) Job status could not be found" 
            exit 1
        }
    }
    END{}

}

function IsJobTerminalState([string]$Status) {
    $TerminalStates = @("Completed", "Failed", "Stopped", "Suspended")
    return $Status -in $TerminalStates
  }
  

## Main Program ##
# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process
# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context
# set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext
Write-Output "Working on subscription $($AzureContext.Subscription) and tenant $($AzureContext.Tenant)"

#Check if runbook is already executing

$jobs = Get-AzAutomationJob -ResourceGroupName $automationRG `
    -AutomationAccountName $automationAccount `
    -RunbookName $runbookName `
    -DefaultProfile $AzureContext

$runningCount = ($jobs.Where( { $_.Status -eq 'Running' })).count

if (($jobs.Status -contains 'Running' -and $runningCount -gt 1 ) -or ($jobs.Status -eq 'New')) {
    Write-Output "Runbook $runbookName is already running"
    exit 1
}
else {
    Write-Output "No concurrent jobs running for $runbookName"
}

if ($WebhookData.RequestBody)
{
   Write-Output "Read input values"
   Write-Output $WebhookData.RequestBody
   $requestparams = ConvertFrom-Json -InputObject $WebhookData.RequestBody
}
elseif (-Not $WebhookData.RequestBody) {
   $requestparams = ConvertFrom-Json -InputObject $WebhookData
}

$promotedVMDetails = Get-AzVM -Name $requestparams.PromotedNode
$demotedVMDetails = Get-AzVM -Name $requestparams.DemotedNode
Write-Output "$(Get-TimeStamp) SAP $($requestparams.ClusterType) database for $($requestparams.SAPSystemId) failed over"
Write-Output " Database running in node $($demotedVMDetails.Name) in Zone $($demotedVMDetails.Zones) switched to node $($promotedVMDetails.Name) running in Zone $($promotedVMDetails.Zones)"
Write-Output ""


# Get list of application server VMs from both Zones

$promotedZoneAppServers,$demotedZoneAppServers = Get-SAPAppInfoByZones -promotedZone $promotedVMDetails.Zones `
                                                                       -demotedZone $demotedVMDetails.Zones `
                                                                       -sapSID $requestparams.SAPSystemId

Write-Output "Application servers to be started running in Zone $($promotedVMDetails.Zones) as $($promotedVMDetails.Name)"
Write-Output $promotedZoneAppServers
Write-Output ""

Write-Output "Application servers to be stopped running in Zone $($demotedVMDetails.Zones) as $($demotedVMDetails.Name)"
Write-Output $demotedZoneAppServers
Write-Output ""

Write-Output "Check if there are enough snoozed app servers avaialble in Promoted Zone"
if (($promotedZoneAppServers.count -eq 0) -or ($promotedZoneAppServers.count -lt $demotedZoneAppServers.count)){
    Write-Output "Application servers switch cannot be performed. Not enough snoozed app servers available"
    exit 1
}
else {
    Write-Output "App Server count in Promoted Zone -> $($promotedZoneAppServers.count)"
    Write-Output "App Server count in Demoted Zone -> $($demotedZoneAppServers.count)"
    Write-Output "Proceeding with the switch"
}

#Start/Stop SAP Application Server
try {
    Write-Output "$(Get-TimeStamp) Starting application servers in Promoted Zone"
    ForEach ($appServerPromote in $promotedZoneAppServers) {
        $promoteJobParams = @{ResourceGroupName = $appServerPromote.appVMRGName;VMName = $appServerPromote.appVMName;SAPApplicationServerWaitTime = $SAPApplicationServerWaitTime}
        Write-Output $promoteJobParams
        $startJob = Start-AzAutomationRunbook -AutomationAccountName $automationAccount `
                                              -Name 'Start-SAPApplicationServer' `
                                              -ResourceGroupName $automationRG `
                                              -DefaultProfile $AzureContext `
                                              -Parameters $promoteJobParams
        $startJobList += @([PSCustomObject]@{
            jobID = $startJob.JobId;
            appServer = $promoteJobParams.VMName;
            Status = "Initiated"
        })
    }
    Write-Output "$(Get-TimeStamp) Jobs scheduled to start Application Servers"
    Write-Output $startJobList
    
    Write-Output "Checking status of the application servers start jobs. Wait for completion"
    $startJobList = Get-SAPAutomationJobStatus -jobList $startJobList `
                                               -automationAccount  $automationAccount `
                                               -automationRG $automationRG
    Write-Output "$(Get-TimeStamp) Final output of jobs"
    Write-Output $startJobList
}

catch {

    Write-Output  $_.Exception.Message
    Write-Output "$(Get-TimeStamp) Application servers in passive zone could not be started. AvZone switch cannot be performed. See previous erros"
    exit 1
}

try{
    #Write-Output "Ensure minimum number of app servers will be honoured before stopping"
    Write-Output "$(Get-TimeStamp) Stopping application servers in Demoted Zone"
    foreach ($appServerDemote in $demotedZoneAppServers) {
        $demoteJobParams = @{ResourceGroupName = $appServerDemote.appVMRGName;VMName = $appServerDemote.appVMName;SAPSoftShutdownTimeInSeconds = $SAPSoftShutdownTimeInSeconds}
        Write-Output $demoteJobParams
        $stopJob = Start-AzAutomationRunbook -AutomationAccountName $automationAccount `
                              -Name 'Stop-SAPApplicationServer' `
                              -ResourceGroupName $automationRG `
                              -DefaultProfile $AzureContext `
                              -Parameters $demoteJobParams
        $stopJobList += @([PSCustomObject]@{
                        jobID = $stopJob.JobId;
                        appServer = $demoteJobParams.VMName;
                        Status = "Initiated"
                        })
    }
    Write-Output "$(Get-TimeStamp) Jobs scheduled to stop application servers"
    Write-Output $stopJobList
    Write-Output "Check status of the application servers stop jobs. Wait for completion"
    $stopJobList = Get-SAPAutomationJobStatus -jobList $stopJobList `
                                               -automationAccount  $automationAccount `
                                               -automationRG $automationRG
    Write-Output "$(Get-TimeStamp) Final output of jobs"
    Write-Output $stopJobList
}
catch {

    Write-Output  $_.Exception.Message
    Write-Output "$(Get-TimeStamp) Application servers could not be stopped. AvZone switch cannot be performed. See previous erros"
    exit 1
}
