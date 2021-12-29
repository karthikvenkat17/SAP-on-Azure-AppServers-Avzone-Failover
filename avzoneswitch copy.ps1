param(
    [Parameter(Mandatory = $true)]
    [object]$WebhookData
)

try{
# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process
# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context
# set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext
Write-Output "Working on subscription $($AzureContext.Subscription) and tenant $($AzureContext.Tenant)"

if ($WebhookData.RequestBody)
{
   Write-Output "Get input values"
   Write-Output $WebhookData.RequestBody
   $requestparams = ConvertFrom-Json -InputObject $WebhookData.RequestBody
   Write-Output $requestparams
   Write-Output "SAP HANA databse for $($requestparams.SAPSystemId) switched from $($requestparams.DemotedNode) to $($requestparams.PromotedNode)"

   Write-Output "Fetching the Zone of Promoted Node"
   $databasevm = Get-AzVM -Name $requestparams.PromotedNode 
   Write-Output "Promoted node $($requestparams.PromotedNode) is running in Zone $($databasevm.Zones)"

   Write-Output "Get all application servers for SAP system $($requestparams.SAPSystemId)"

#Test if Tag 'SAPSystemSID' with value $SAPSID exist. If not exit
Test-AzSAPSIDTagExist -SAPSID $requestparams.SAPSystemId

# Get SAP Appplication VMs
$SAPSIDApplicationVMs  = Get-AzSAPApplicationInstances -SAPSID $requestparams.SAPSystemId

Write-Output "$SAPSIDApplicationVMs"

# List SAP Application layer VM
#Write-WithTime "SAP Application layer VMs:"
#$appserverlist = Show-AzSAPSIDVMApplicationInstances -SAPVMs $SAPSIDApplicationVMs
#Write-Output $appserverlist
#foreach ($appvm in $appserverlist ) {
    # Get Zone of app server
#    $vmdetails = Get-AzVM -Name $appvm.VMName -ResourceGroupName $appvm.ResourceGroupName
#    Write-output "$($appvm.VMName) runs in Zone $($vmdetails.Zones)" 
    #if ($appvm.zone -ceq $databasevm.Zones) {
    #Write-Output "Application Server $($appvm.name) runs in same zone as database"
    #}
    #}
#    }

#else {
#    Write-Output "PS called without parameters"
#}
}
}
catch
{
    Write-Output $_.Exception.Message`n
    Write-Output "AvZone switch failed See previous errors"
    Exit 1
}