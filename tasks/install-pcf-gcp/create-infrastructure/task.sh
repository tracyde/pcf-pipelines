#!/bin/bash
set -e

root=$PWD

# us: ops-manager-us/pcf-gcp-1.9.2.tar.gz -> ops-manager-us/pcf-gcp-1.9.2.tar.gz
pcf_opsman_bucket_path=$(grep -i 'us:.*.tar.gz' pivnet-opsmgr/*GCP.yml | cut -d' ' -f2)

# ops-manager-us/pcf-gcp-1.9.2.tar.gz -> opsman-pcf-gcp-1-9-2
pcf_opsman_image_name=$(echo $pcf_opsman_bucket_path | sed 's%.*/\(.*\).tar.gz%opsman-\1%' | sed 's/\./-/g')

ert_sql_instance_name="${GCP_RESOURCE_PREFIX}-sql-$(cat /proc/sys/kernel/random/uuid)"

pcf_ert_ssl_cert=$PCF_ERT_SSL_CERT
pcf_ert_ssl_key=$PCF_ERT_SSL_KEY

if [[ ${PCF_ERT_SSL_CERT} == "generate" ]]; then
  echo "Generating Self Signed Certs for sys.${PCF_ERT_DOMAIN} & cfapps.${PCF_ERT_DOMAIN} ..."
  pcf-pipelines/tasks/scripts/gen_ssl_certs.sh "sys.${PCF_ERT_DOMAIN}" "cfapps.${PCF_ERT_DOMAIN}"
  pcf_ert_ssl_cert=$(cat sys.${PCF_ERT_DOMAIN}.crt)
  pcf_ert_ssl_key=$(cat sys.${PCF_ERT_DOMAIN}.key)
fi

export GOOGLE_CREDENTIALS=${GCP_SERVICE_ACCOUNT_KEY}
export GOOGLE_PROJECT=${GCP_PROJECT_ID}
export GOOGLE_REGION=${GCP_REGION}

terraform plan \
  -var "gcp_proj_id=${GCP_PROJECT_ID}" \
  -var "gcp_region=${GCP_REGION}" \
  -var "gcp_zone_1=${GCP_ZONE_1}" \
  -var "gcp_zone_2=${GCP_ZONE_2}" \
  -var "gcp_zone_3=${GCP_ZONE_3}" \
  -var "prefix=${GCP_RESOURCE_PREFIX}" \
  -var "pcf_opsman_image_name=${pcf_opsman_image_name}" \
  -var "pcf_ert_domain=${PCF_ERT_DOMAIN}" \
  -var "pcf_ert_ssl_cert=${pcf_ert_ssl_cert}" \
  -var "pcf_ert_ssl_key=${pcf_ert_ssl_key}" \
  -var "ert_sql_instance_name=${ert_sql_instance_name}" \
  -var "ert_sql_db_username=${ERT_SQL_DB_USERNAME}" \
  -var "ert_sql_db_password=${ERT_SQL_DB_PASSWORD}" \
  -out terraform.tfplan \
  -state terraform-state/terraform.tfstate \
  pcf-pipelines/tasks/install-pcf-gcp/terraform/$gcp_pcf_terraform_template

terraform apply \
  -state-out $root/create-infrastructure-output/terraform.tfstate \
  terraform.tfplan

cd $root/create-infrastructure-output
  output_json=$(terraform output -json -state=terraform.tfstate)
  pub_ip_global_pcf=$(echo $output_json | jq --raw-output '.pub_ip_global_pcf.value')
  pub_ip_ssh_and_doppler=$(echo $output_json | jq --raw-output '.pub_ip_ssh_and_doppler.value')
  pub_ip_ssh_tcp_lb=$(echo $output_json | jq --raw-output '.pub_ip_ssh_tcp_lb.value')
  pub_ip_opsman=$(echo $output_json | jq --raw-output '.pub_ip_opsman.value')
cd -

echo "Please configure DNS as follows:"
echo "----------------------------------------------------------------------------------------------"
echo "*.sys.${PCF_ERT_DOMAIN} == ${pub_ip_global_pcf}"
echo "*.cfapps.${PCF_ERT_DOMAIN} == ${pub_ip_global_pcf}"
echo "ssh.sys.${PCF_ERT_DOMAIN} == ${pub_ip_ssh_and_doppler}"
echo "doppler.sys.${PCF_ERT_DOMAIN} == ${pub_ip_ssh_and_doppler}"
echo "loggregator.sys.${PCF_ERT_DOMAIN} == ${pub_ip_ssh_and_doppler}"
echo "tcp.${PCF_ERT_DOMAIN} == ${pub_ip_ssh_tcp_lb}"
echo "opsman.${PCF_ERT_DOMAIN} == ${pub_ip_opsman}"
echo "----------------------------------------------------------------------------------------------"
