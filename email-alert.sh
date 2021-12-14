#/bin/bash
## Email alerts for SAP failover.
## crm config:  alert email-alert "/usr/share/pacemaker/alerts/email-alert.sh" 

resource=$(crm resource status |grep -i Hana|sed -n -e '/\[[^]]/s/^[^[]*\[\([^]]*\)].*$/\1/p'|tail -1)
if [ -z "$resource" ];then
  echo "SAP HANA Cluster resource not found"
  exit
fi

if [ "$CRM_alert_task" = "promote" ];then
if [ "$resource" = "$CRM_alert_rsc" ];then
  time=$(date)
  echo "SAP resource $CRM_alert_rsc has migrated at $CRM_alert_timestamp " > /tmp/ha-alert.$CRM_alert_timestamp 

echo "Resource $CRM_alert_rsc reported action of \"$CRM_alert_task\""  >> /tmp/ha-alert.$CRM_alert_timestamp

  echo " " >> /tmp/ha-alert.$CRM_alert_timestamp
  echo "Cluster Monitor:" >> /tmp/ha-alert.$CRM_alert_timestamp
  sleep 10
  crm_mon -1 >> /tmp/ha-alert.$CRM_alert_timestamp


#  sender=$(hostname)
#  mail -s "$sid $app Migrated at $time" -r $sender user@xyz.com < /tmp/ha-alert.$CRM_alert_timestamp

fi
fi
