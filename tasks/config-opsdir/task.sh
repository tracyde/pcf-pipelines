#!/bin/bash -e

function fn_get_azs {
     local azs_csv=$1
     echo $azs_csv | jq --raw-input 'split(",")'
}

IAAS_CONFIGURATION=$(cat <<-EOF
{
  "vcenter_host": "$VCENTER_HOST",
  "vcenter_username": "$VCENTER_USR",
  "vcenter_password": "$VCENTER_PWD",
  "datacenter": "$VCENTER_DATA_CENTER",
  "disk_type": "$VCENTER_DISK_TYPE",
  "ephemeral_datastores_string": "$EPHEMERAL_STORAGE_NAMES",
  "persistent_datastores_string": "$PERSISTENT_STORAGE_NAMES",
  "bosh_vm_folder": "pcf_vms",
  "bosh_template_folder": "pcf_templates",
  "bosh_disk_path": "pcf_disk",
  "ssl_verification_enabled": false
}
EOF
)

AZ_CONFIGURATION=$(cat <<-EOF
{
  "availability_zones": [
    {
      "name": "$AZ_1",
      "cluster": "$AZ_1_CLUSTER_NAME",
      "resource_pool": "$AZ_1_RP_NAME"
    }
  ]
}
EOF
)

INFRA_AZS=$(fn_get_azs "$INFRA_NW_AZS")
DEPLOYMENT_AZS=$(fn_get_azs "$DEPLOYMENT_NW_AZS")

NETWORK_CONFIGURATION=$(cat <<-EOF
{
  "icmp_checks_enabled": $ICMP_CHECKS_ENABLED,
  "networks": [
    {
      "name": "$INFRA_NETWORK_NAME",
      "service_network": false,
      "subnets": [
        {
          "iaas_identifier": "$INFRA_VCENTER_NETWORK",
          "cidr": "$INFRA_NW_CIDR",
          "reserved_ip_ranges": "$INFRA_EXCLUDED_RANGE",
          "dns": "$INFRA_NW_DNS",
          "gateway": "$INFRA_NW_GATEWAY",
          "availability_zone_names": $INFRA_AZS
        }
      ]
    },
    {
      "name": "$DEPLOYMENT_NETWORK_NAME",
      "service_network": false,
      "subnets": [
        {
          "iaas_identifier": "$DEPLOYMENT_VCENTER_NETWORK",
          "cidr": "$DEPLOYMENT_NW_CIDR",
          "reserved_ip_ranges": "$DEPLOYMENT_EXCLUDED_RANGE",
          "dns": "$DEPLOYMENT_NW_DNS",
          "gateway": "$DEPLOYMENT_NW_GATEWAY",
          "availability_zone_names": $DEPLOYMENT_AZS
        }
      ]
    }
  ]
}
EOF
)

DIRECTOR_CONFIG=$(cat <<-EOF
{
  "ntp_servers_string": "$NTP_SERVERS",
  "resurrector_enabled": $ENABLE_VM_RESURRECTOR,
  "max_threads": $MAX_THREADS,
  "database_type": "internal",
  "blobstore_type": "local",
  "director_hostname": "$OPS_DIR_HOSTNAME"
}
EOF
)

SECURITY_CONFIG=$(cat <<-EOF
{
  "security_configuration": {
    "generate_vm_passwords": $GENERATE_VM_PASSWORDS,
    "trusted_certificates": "$TRUSTED_CERTIFICATES"
  }
}
EOF
)

INFRA_FIRST_AZ=$(echo $INFRA_AZS | jq --raw-output '.[0]')

NETWORK_ASSIGNMENT=$(cat <<-EOF
{
  "network_and_az": {
     "network": {
       "name": "$INFRA_NETWORK_NAME"
     },
     "singleton_availability_zone": {
       "name": "$INFRA_FIRST_AZ"
     }
  }
}
EOF
)

echo "Configuring IaaS and Director..."
om-linux \
  --target https://$OPS_MGR_HOST \
  --skip-ssl-validation \
  --username $OPS_MGR_USR \
  --password $OPS_MGR_PWD \
  configure-bosh \
  --iaas-configuration "$IAAS_CONFIGURATION" \
  --director-configuration "$DIRECTOR_CONFIG"

echo "Configuring availability zones..."
om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
  curl -p "/api/v0/staged/director/availability_zones" \
  -x PUT -d "$AZ_CONFIGURATION"

echo "Configuring networks..."
om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
  curl -p "/api/v0/staged/director/networks" \
  -x PUT -d "$NETWORK_CONFIGURATION"

echo "Configuring network assignment..."
om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
  curl -p "/api/v0/staged/director/network_and_az" \
  -x PUT -d "$NETWORK_ASSIGNMENT"

echo "Configuring security..."
om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
  curl -p "/api/v0/staged/director/properties" \
  -x PUT -d "$SECURITY_CONFIG"
