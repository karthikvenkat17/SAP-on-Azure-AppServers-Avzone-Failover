param(
    [Parameter(Mandatory = $true)]
    [object]$WebhookData
)
Set-PSDebug -Trace 2
try {
# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

Write-Output $AzureContext.Subscription
# set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

if ($WebhookData.RequestBody)
{
   Write-Output "Get input values"
   Write-Output $WebhookData.RequestBody
   $requestparams = ConvertFrom-Json -InputObject $WebhookData.RequestBody
   Write-Output $requestparams
   Write-Output "SAP HANA databse for $($requestparams.SAPSystemId) switched from $($requestparams.DemotedNode) to $($requestparams.PromotedNode)"

   Write-Output "Fetching the Zone of Promoted Node"
   $databasevm = Get-AzVM -Name $requestparams.PromotedNode 
   Write-Output $databasevm
   Write-Output "Promote node $($requestparams.PromotedNode) is running in Zone $($databasevm.Zones)"

   Write-Output "Get all application servers for SAP system $($requestparams.SAPSystemId)"
   $tags = @{"SAPSystemSID" = $SAPSID }
   $appvmlist =  Get-AzResource -ResourceType "Microsoft.Compute/virtualMachines"  -Tag $tags
   foreach ($appvm in $appvmlist ) {
       if ($appvm.zone -ceq $databasevm.Zones) {
       Write-Output "Application Server $($appvm.name) runs in same zone as database"
       }
   }
    

}

else {
    Write-Output "PS called without parameters"
}
}
catch
{
    Write-Output $_.Exception.Message`n
    Write-Output "AvZone switch failed See previous errors"
    Exit 1
}