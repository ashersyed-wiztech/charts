#!/bin/bash

set -x

helm init --client-only

mapfile -t repos < <(helm repo list)
for ((i = 1; i < ${#repos[@]}; ++i)); do 
    # echo ${repos[$i]}; 
    repo=$(echo ${repos[$i]} | cut -d' ' -f 1)
    helm repo remove ${repo}
done

helm repo add private http://172.19.3.13:8080
helm repo update

curl --header "PRIVATE-TOKEN: RRB-5Wesw99zMd3sjpxm" 'http://172.19.53.32/api/v4/projects' -o projects.json
curl --header "PRIVATE-TOKEN: RRB-5Wesw99zMd3sjpxm" 'http://172.19.53.32/api/v4/projects/1/jobs?scope[]=success' -o jobs.json

COMMIT_ID=$(cat jobs.json |  jq '.[0].commit.short_id')
COMMIT_ID=${COMMIT_ID//\"/}
RELEASE_NAME="odoo-clone-1-${COMMIT_ID}"

# building postgresql for dependency resolution
pushd stable/postgresql
rm -rf postgresql-*.tgz
helm package .
curl -X "DELETE" http://172.19.3.13:8080/api/charts/postgresql/3.16.1
curl -L --data-binary "@postgresql-3.16.1.tgz" http://172.19.3.13:8080/api/charts
popd 

pushd stable/odoo-clone-1
rm -rf odoo-clone-1-*.tgz

version=$(grep 'version' Chart.yaml)
appVersion=$(grep 'appVersion' Chart.yaml)

currentVersion=$(echo ${version} | cut -d':' -f 2)
newVersion=$(echo ${currentVersion} | awk -F. -v OFS=. 'NF==1{print ++$NF}; NF>1{if(length($NF+1)>length($NF))$(NF-1)++; $NF=sprintf("%0*d", length($NF), ($NF+1)%(10^length($NF))); print}')

currentAppVersion=$(echo ${appVersion} | cut -d':' -f 2)
currentMajorVersion=$(echo ${currentAppVersion} | cut -d'.' -f 1)
currentMinorVersion=$(echo ${currentAppVersion} | cut -d'.' -f 2)
currentDateTime=$(date +"%Y%m%d%H%M")
newAppVersion="${currentMajorVersion}.${currentMinorVersion}.${currentDateTime}-${COMMIT_ID}"

sed -i "s/${version}/version: ${newVersion}/" Chart.yaml
sed -i "s/${appVersion}/appVersion: ${newAppVersion}/" Chart.yaml

helm dependency update
helm package .
curl -X "DELETE" "http://172.19.3.13:8080/api/charts/odoo-clone-1/${newVersion}"
curl -L --data-binary "@odoo-clone-1-${newVersion}.tgz" http://172.19.3.13:8080/api/charts

exists=$(helm ls odoo-clone-1-12)
if [[ "$exists" != "" ]]; then
    helm del --purge odoo-clone-1-12    
fi
sleep 10

helm repo update
helm install --name odoo-clone-1-12 private/odoo-clone-1

pushd

set +x 
