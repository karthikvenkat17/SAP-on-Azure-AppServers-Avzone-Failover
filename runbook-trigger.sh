#/bin/bash
## Trigger Azure automation runbook 
## crm config:  alert email-alert "/usr/share/pacemaker/alerts/email-alert.sh" 
set -x
resource=$(crm resource status |grep -i Hana|sed -n -e '/\[[^]]/s/^[^[]*\[\([^]]*\)].*$/\1/p'|tail -1)
if [ -z "$resource" ];then
  echo "SAP HANA database resource not found"
  exit
else
ClusterType=HANA
fi

if [ "$CRM_alert_task" = "promote" ];then
if [ "$resource" = "$CRM_alert_rsc" ];then
  PromotedNode=$(crm node show | grep -i member | grep -i $CRM_alert_node | cut -d "(" -f 1)
  DemotedNode=$(crm node show | grep -i member | grep -iv $CRM_alert_node  | cut -d "(" -f 1)
  SAPSystemId=$(crm configure show $CRM_alert_rsc | awk '/SID/ {print $2}' | cut -d '=' -f 2)

if [ -z "$PromotedNode" || -z "$DemotedNode" || -z "$SAPSystemId" ];then
  echo "SAP Cluster node information cannot be found"
  exit 
fi

echo "{"\"ClusterType"\":"\"$ClusterType"\","\"SAPSystemId"\":"\"$SAPSystemId"\","\"PromotedNode"\":"\"$PromotedNode"\","\"DemotedNode"\":"\"$DemotedNode"\"}" > /tmp/ha-alert.$CRM_alert_timestamp.json 
  
## Trigger automation runbook

jobid=$(curl -d "@/tmp/ha-alert.$CRM_alert_timestamp.json" -X POST https://xxx.webhook.xx.azure-automation.net/webhooks?token=xxxxxx

echo "SAP resource $CRM_alert_rsc has migrated at $CRM_alert_timestamp " > /tmp/ha-alert.$CRM_alert_timestamp 

echo "Resource $CRM_alert_rsc reported action of \"$CRM_alert_task\""  >> /tmp/ha-alert.$CRM_alert_timestamp

  echo " " >> /tmp/ha-alert.$CRM_alert_timestamp
  echo "Cluster Monitor:" >> /tmp/ha-alert.$CRM_alert_timestamp
  sleep 10
  crm_mon -1 >> /tmp/ha-alert.$CRM_alert_timestamp

echo "Automation runbook with $jobid scheduled"

fi
fi
