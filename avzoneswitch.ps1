param(
    [Parameter(Mandatory = $true)]
    [object]$WebhookData,
    # Automation account parameters
    [Parameter(Mandatory = $true)]
    [String]$automationAccount,
    [Parameter(Mandatory = $true)]
    [String]$automationRG
)


Set-PSDebug -Trace 2
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
            $appVMlist = Get-AzResource -ResourceType "Microsoft.Compute/virtualMachines"  -Tag $tags | Where-Object { ($_.Tags.Item("SAPApplicationInstanceType") -EQ 'SAP_D') -or ($_.Tags.Item("SAPApplicationInstanceType") -EQ 'SAP_DVEBMGS') } 
            #[string[]]$promotedZoneAppServers = @()
            #[string[]]$demotedZoneAppServers = @() 
            foreach ($appVM in $appVMlist) {
            $vmInfo =  Get-AzVM -Name $appvm.Name -ResourceGroupName $appVM.ResourceGroupName
            #Write-output "Avzone info $($vmInfo.Name) zone $($vmInfo.Zones)"
            if ($vmInfo.Zones -eq $promotedZone) {
                $promotedZoneAppServers += [PSCustomObject]@{
                    appVMName = $vmInfo.Name
                    appVMRGName = $vmInfo.ResourceGroupName
                    appZone = $vmInfo.Zones
                }
                }
               elseif ($vmInfo.Zones -eq $demotedZone){
                $demotedZoneAppServers += [PSCustomObject]@{
                    appVMName = $vmInfo.Name
                    appVMRGName = $vmInfo.ResourceGroupName
                    appZone = $vmInfo.Zones
                }
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
    }    
    }
    END {}

}

function Get-SAPAutomationJobStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCUstomObject]$jobList,
        [Parameter(Mandatory = $true)]
        [String]$automationRG,
        [Parameter(Mandatory = $true)]
        [String]$automationAccount
    )
    BEGIN {}
    PROCESS {
        try {
            $PollingSeconds = 5
            $MaxTimeout = New-TimeSpan -Hours 1 | Select-Object -ExpandProperty TotalSeconds
            $WaitTime = 0
            foreach ($job in $jobList) {
                $jobDetail = Get-AzAutomationJob -Id $job.JobID -ResourceGroupName $automationRG -AutomationAccountName $automationAccount
                while(-NOT (IsJobTerminalState $jobDetail.Status) -and $WaitTime -lt $MaxTimeout) {
                    Start-Sleep -Seconds $PollingSeconds
                    $WaitTime += $PollingSeconds
                    $jobDetail = $jobDetail | Get-AzAutomationJob
                 }
                 $obj = $jobList | Where-Object {$_.jobID -eq $job.jobID}
                 if ($jobDetail.Status -eq "Completed") {
                    $obj.Status = "Success"
                    }
                    else{
                    $obj.Status = "NotSuccess"
                    }          
                return $jobList
            }
        }
        catch {
            Write-Output  $_.Exception.Message
            Write-Output "Job status could not be found" 
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
Write-Output "SAP HANA databse for $($requestparams.SAPSystemId) failed over"
Write-Output "$($demotedVMDetails.Name) running Zone $($demotedVMDetails.Zones)  -> $($promotedVMDetails.Name) running Zone $($promotedVMDetails.Zones)"
Write-Output ""


# Get list of application server VMs from both Zones

$promotedZoneAppServers,$demotedZoneAppServers = Get-SAPAppInfoByZones -promotedZone $promotedVMDetails.Zones -demotedZone $demotedVMDetails.Zones -sapSID $requestparams.SAPSystemId

Write-Output "Application servers to be started running in Zone $($promotedVMDetails.Zones) as $($promotedVMDetails.Name)"
Write-Output $promotedZoneAppServers
Write-Output ""

Write-Output "Application servers to be stopped running in Zone $($demotedVMDetails.Zones) as $($demotedVMDetails.Name)"
Write-Output $demotedZoneAppServers
Write-Output ""

#Start/Stop SAP Application Server
try {
    Write-Output "Starting application servers"
    ForEach ($appServerPromote in $promotedZoneAppServers) {
        $promoteJobParams = @{ResourceGroupName = $appServerPromote.appVMRGName;VMName = $appServerPromote.appVMName}
        Write-Output $promoteJobParams
        $startJob = Start-AzAutomationRunbook -AutomationAccountName $automationAccount `
                                        -Name 'Start-SAPApplicationServer' `
                                        -ResourceGroupName $automationRG `
                                        -DefaultProfile $AzureContext `
                                        -Parameters $promoteJobParams
        #$doLoop = (($status -ne "Completed") -and ($status -ne "Failed") -and ($status -ne "Suspended") -and ($status -ne "Stopped"))
        $startJobList += [PSCustomObject]@{
            jobID = $startJob.JobId
            appServer = $promoteJobParams.VMName
            Status = "Started"
        }
     Write-Output "Jobs scheduled to start Application Servers"
     Write-Output $startJobList
    }

    Write-Output "Check status of the application servers start jobs. Wait for completion"
    $startJobList = Get-SAPAutomationJobStatus -jobList $startJobList `
                                               -automationAccount  $automationAccount `
                                               -automationRG $automationRG
    Write-Output "Final output of jobs"
    Write-Output $startJobList
}

catch {

    Write-Output  $_.Exception.Message
    Write-Output "Application servers could not be started. AvZone switch cannot be performed. See previous erros"
}

try{    
    foreach ($appServerDemote in $demotedZoneAppServers) {
        $demoteJobParams = @{ResourceGroupName = $appServerDemote.appVMRGName;VMName = $appServerDemote.appVMName}
        Write-Output $demoteJobParams
        $stopJob = Start-AzAutomationRunbook -AutomationAccountName $automationAccount `
                              -Name 'Stop-SAPApplicationServer' `
                              -ResourceGroupName $automationRG `
                              -DefaultProfile $AzureContext `
                              -Parameters $demoteJobParams
        $stopJobList += [PSCustomObject]@{
                        jobID = $stopJob.JobId
                        appServer = $demoteJobParams.VMName
                        Status = "Started"
    }
    Write-Output "Jobs scheduled to stop application servers"
    Write-Output $stopJobList
    Write-Output "Check status of the application servers stop jobs. Wait for completion"
    $stopJobList = Get-SAPAutomationJobStatus -jobList $stopJobList `
                                               -automationAccount  $automationAccount `
                                               -automationRG $automationRG
    Write-Output "Final output of jobs"
    Write-Output $stopJobList
}
}
catch {

    Write-Output  $_.Exception.Message
    Write-Output "Application servers could not be stopped. AvZone switch cannot be performed. See previous erros"
}




