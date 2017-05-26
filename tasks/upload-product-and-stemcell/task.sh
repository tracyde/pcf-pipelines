#!/bin/bash -e

if [[ ! -z "$NO_PROXY" ]]; then
  echo "$OM_IP $OPS_MGR_HOST" >> /etc/hosts
fi

STEMCELL_VERSION=`cat ./pivnet-product/metadata.json | jq --raw-output '.Dependencies[] | select(.Release.Product.Name | contains("Stemcells")) | .Release.Version'`

if [ -n "$STEMCELL_VERSION" ]; then
  stemcell_exists=$(om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl --silent --path "/api/v0/diagnostic_report" | jq '.stemcells' | grep $STEMCELL_VERSION | grep -c ${STEMCELL_GLOB//\*/})

  if [[ "$stemcell_exists" -eq "0" ]]; then
    echo "Downloading stemcell $STEMCELL_VERSION"
    pivnet-cli login --api-token="$PIVNET_API_TOKEN"
    pivnet-cli download-product-files -p stemcells -r $STEMCELL_VERSION -g $STEMCELL_GLOB --accept-eula

    SC_FILE_PATH=`find ./ -name *.tgz`

    if [ ! -f "$SC_FILE_PATH" ]; then
      echo "Stemcell file not found!"
      exit 1
    fi

    om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k upload-stemcell -s $SC_FILE_PATH

    echo "Removing downloaded stemcell $STEMCELL_VERSION"
    rm $SC_FILE_PATH
  fi
fi

FILE_PATH=`find ./pivnet-product -name *.pivotal`
om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k upload-product -p $FILE_PATH
