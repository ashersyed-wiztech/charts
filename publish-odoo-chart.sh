#!/bin/bash

curl --header "PRIVATE-TOKEN: RRB-5Wesw99zMd3sjpxm" 'http://172.19.53.32/api/v4/projects' -o projects.json
curl --header "PRIVATE-TOKEN: RRB-5Wesw99zMd3sjpxm" 'http://172.19.53.32/api/v4/projects/1/jobs?scope[]=success' -o jobs.json

COMMIT_ID=$(cat jobs.json |  jq '.[0].commit.short_id')
COMMIT_ID=${COMMIT_ID//\"/}
RELEASE_NAME="odoo-${COMMIT_ID}"

pushd stable/odoo
rm -rf odoo-*.tgz

version=$(grep 'version' Chart.yaml)
appVersion=$(grep 'appVersion' Chart.yaml)

currentVersion=$(echo ${version} | cut -d':' -f 2)
newVersion=$(echo ${currentVersion} | awk -F. -v OFS=. 'NF==1{print ++$NF}; NF>1{if(length($NF+1)>length($NF))$(NF-1)++; $NF=sprintf("%0*d", length($NF), ($NF+1)%(10^length($NF))); print}')

currentAppVersion=$(echo ${appVersion} | cut -d':' -f 2)
currentMajorVersion=$(echo ${currentAppVersion} | cut -d':' -f 1)
currentMinorVersion=$(echo ${currentAppVersion} | cut -d':' -f 2)
currentDateTime=$(date +"%Y%m%d%H%M")
newAppVersion="${currentMajorVersion}.${currentMinorVersion}.${currentDateTime}-${COMMIT_ID}"

sed -i 's/${version}/version: ${newVersion}/' Chart.yaml
sed -i 's/${appVersion}/appVersion: ${newAppVersion}/' Chart.yaml

helm package .
curl -L --data-binary "@odoo-${newVersion}.tgz" http://172.19.3.13:8080/api/charts

mapfile -t repos < <(helm repo list)
for ((i = 1; i < ${#repos[@]}; ++i)); do 
    # echo ${repos[$i]}; 
    repo=$(echo ${repos[$i]} | cut -d' ' -f 1)
    helm remove repo ${repo}
done

helm repo add private http://172.19.3.13:8080
helm repo update

exists=$(helm ls ${RELEASE_NAME})
if [[ "$exists" != "" ]]; then
    helm del --purge ${RELEASE_NAME}    
fi
sleep 10

helm install --name ${RELEASE_NAME} private/odoo

pushd
