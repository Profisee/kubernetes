#!/bin/bash
#install the aks cli since this script runs in az 2.0.80 and the az aks was not added until 2.5
az aks install-cli;
#get the aks creds, this allows us to use kubectl commands if needed
az aks get-credentials --resource-group $RESOURCEGROUPNAME --name $CLUSTERNAME --overwrite-existing;

#install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3;
chmod 700 get_helm.sh;
./get_helm.sh;

#install nginx
helm repo add stable https://kubernetes-charts.storage.googleapis.com/;
#get profisee nginx settings
curl -fsSL -o nginxSettings.yaml https://raw.githubusercontent.com/Profisee/kubernetes/Azure-Powershell/master/scripts/nginxSettings.yaml;
helm uninstall nginx
helm install nginx stable/nginx-ingress --values nginxSettings.yaml --set controller.service.loadBalancerIP=$publicInIP;

#wait for the ip to be available.  usually a few seconds
sleep 30;
#get ip for nginx
nginxip=$(kubectl get services nginx-nginx-ingress-controller --output="jsonpath={.status.loadBalancer.ingress[0].ip}");
echo $nginxip;

#fix tls variables
#cert
if [ "$CONFIGUREHTTPS" = "Yes" ]; then
	printf '%s\n' "$TLSCERT" | sed 's/- /-\n/g; s/ -/\n-/g' | sed '/CERTIFICATE/! s/ /\n/g' >> a.cert;
	sed -e 's/^/    /' a.cert > tls.cert;
else    
    echo '    NA' > tls.cert;
fi
rm a.cert

#key
if [ "$CONFIGUREHTTPS" = "Yes" ]; then
    printf '%s\n' "$TLSKEY" | sed 's/- /-\n/g; s/ -/\n-/g' | sed '/PRIVATE/! s/ /\n/g' >> a.key;
	sed -e 's/^/    /' a.key > tls.key;
else
	echo '    NA' > tls.key;	    
fi
rm a.key

#set dns
if [ "$UPDATEDNS" = "Yes" ]; then
	az network dns record-set a delete -g $DOMAINNAMERESOURCEGROUP -z $DNSDOMAINNAME -n $DNSHOSTNAME --yes;
	az network dns record-set a add-record -g $DOMAINNAMERESOURCEGROUP -z $DNSDOMAINNAME -n $DNSHOSTNAME -a $nginxip --ttl 5;
fi

#install profisee platform
#set profisee helm chart settings
curl -fsSL -o Settings.yaml https://raw.githubusercontent.com/profisee/Azure-ARM/master/Settings.yaml
auth="$(echo -n "$ACRUSER:$ACRUSERPASSWORD" | base64)"
sed -i -e 's/$ACRUSER/'"$ACRUSER"'/g' Settings.yaml
sed -i -e 's/$ACRPASSWORD/'"$ACRUSERPASSWORD"'/g' Settings.yaml
sed -i -e 's/$ACREMAIL/'"support@profisee.com"'/g' Settings.yaml
sed -i -e 's/$ACRAUTH/'"$auth"'/g' Settings.yaml
sed -e '/$TLSCERT/ {' -e 'r tls.cert' -e 'd' -e '}' -i Settings.yaml
sed -e '/$TLSKEY/ {' -e 'r tls.key' -e 'd' -e '}' -i Settings.yaml

#create the azure app id (clientid)
azureAppReplyUrl="${EXTERNALDNSURL}/profisee/auth/signin-microsoft"
if [ "$UPDATEAAD" = "Yes" ]; then
	azureClientName="${RESOURCEGROUPNAME}_${CLUSTERNAME}";
	CLIENTID=$(az ad app create --display-name $azureClientName --reply-urls $azureAppReplyUrl --query 'appId');
	#clean client id - remove quotes
	CLIENTID=$(echo "$CLIENTID" | tr -d '"')
	#add a Graph API permission of "Sign in and read user profile"
	az ad app permission add --id $CLIENTID --api 00000002-0000-0000-c000-000000000000 --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope
	az ad app permission grant --id $CLIENTID --api 00000002-0000-0000-c000-000000000000
fi

#get storage account pw - if not supplied
if ["$FILEREPOPASSWORD" = ""]; then
	FILEREPOPASSWORD=$(az storage account keys list --resource-group $RESOURCEGROUPNAME --account-name $STORAGEACCOUNTNAME --query '[0].value');
	#clean file repo password - remove quotes
	FILEREPOPASSWORD=$(echo "$FILEREPOPASSWORD" | tr -d '"')
fi

#storage vars
FILEREPOUSERNAME="Azure\\\\\\\\${STORAGEACCOUNTNAME}"
FILEREPOURL="\\\\\\\\\\\\\\\\${STORAGEACCOUNTNAME}.file.core.windows.net\\\\\\\\${STORAGEACCOUNTFILESHARENAME}"

if [ "$PROFISEEVERSION" = "2020 R1" ]; then
    ACRREPONAME='profisee2020r1';
	ACRREPOLABEL='GA';
else
    ACRREPONAME='profisee2020r2';
	ACRREPOLABEL='latest';
fi

#set values in Settings.yaml
sed -i -e 's/$SQLNAME/'"$SQLNAME"'/g' Settings.yaml
sed -i -e 's/$SQLDBNAME/'"$SQLDBNAME"'/g' Settings.yaml
sed -i -e 's/$SQLUSERNAME/'"$SQLUSERNAME"'/g' Settings.yaml
sed -i -e 's/$SQLUSERPASSWORD/'"$SQLUSERPASSWORD"'/g' Settings.yaml
sed -i -e 's/$FILEREPOUSERNAME/'"$FILEREPOUSERNAME"'/g' Settings.yaml
sed -i -e 's~$FILEREPOPASSWORD~'"$FILEREPOPASSWORD"'~g' Settings.yaml
sed -i -e 's/$FILEREPOURL/'"$FILEREPOURL"'/g' Settings.yaml
sed -i -e 's~$OIDCURL~'"$OIDCURL"'~g' Settings.yaml
sed -i -e 's/$CLIENTID/'"$CLIENTID"'/g' Settings.yaml
sed -i -e 's/$OIDCCLIENTSECRET/'"$OIDCCLIENTSECRET"'/g' Settings.yaml
sed -i -e 's/$ADMINACCOUNTNAME/'"$ADMINACCOUNTNAME"'/g' Settings.yaml
sed -i -e 's/$EXTERNALDNSURL/'"$EXTERNALDNSURL"'/g' Settings.yaml
sed -i -e 's/$EXTERNALDNSNAME/'"$EXTERNALDNSNAME"'/g' Settings.yaml
sed -i -e 's~$LICENSEDATA~'"$LICENSEDATA"'~g' Settings.yaml
sed -i -e 's/$ACRREPONAME/'"$ACRREPONAME"'/g' Settings.yaml
sed -i -e 's/$ACRREPOLABEL/'"$ACRREPOLABEL"'/g' Settings.yaml

helm repo add profisee https://profisee.github.io/kubernetes
helm uninstall profiseeplatform2020r1
helm install profiseeplatform2020r1 profisee/profisee-platform --values Settings.yaml

result="{\"Result\":[\
{\"IP\":\"$nginxip\"},\
{\"WEBURL\":\"${EXTERNALDNSURL}/Profisee\"},\
{\"FILEREPOUSERNAME\":\"$FILEREPOUSERNAME\"},\
{\"FILEREPOURL\":\"$FILEREPOURL\"},\
{\"AZUREAPPCLIENTID\":\"$CLIENTID\"},\
{\"AZUREAPPREPLYURL\":\"$azureAppReplyUrl\"},\
{\"ACRREPONAME\":\"$ACRREPONAME\"},\
{\"ACRREPOLABEL\":\"$ACRREPOLABEL\"}\
]}"
echo $result > $AZ_SCRIPTS_OUTPUT_PATH
