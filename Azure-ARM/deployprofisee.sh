#!/bin/bash
REPONAME="profisee"
REPOURL="https://raw.githubusercontent.com/$REPONAME/kubernetes/master";
HELMREPOURL="https://$REPONAME.github.io/kubernetes";
echo $"REPOURL is $REPOURL";
echo $"HELMREPOURL is $HELMREPOURL";

az login --identity
#install the aks cli since this script runs in az 2.0.80 and the az aks was not added until 2.5
az aks install-cli;
#get the aks creds, this allows us to use kubectl commands if needed
az aks get-credentials --resource-group $RESOURCEGROUPNAME --name $CLUSTERNAME --overwrite-existing;

#install dotnet core
echo $"Installing dotnet core started";
curl -fsSL -o dotnet-install.sh https://dot.net/v1/dotnet-install.sh
#set permisssions
chmod 755 ./dotnet-install.sh
#install dotnet
./dotnet-install.sh -c Current
echo $"Installing dotnet core finished";

#Downloadind and extracting license reader
echo $"Downloading and extracting license reader started";
curl -fsSL -o LicenseReader.tar.001 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.001"
curl -fsSL -o LicenseReader.tar.002 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.002"
curl -fsSL -o LicenseReader.tar.003 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.003"
curl -fsSL -o LicenseReader.tar.004 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.004"
cat LicenseReader.tar.* | tar xf -
rm LicenseReader.tar.001
rm LicenseReader.tar.002
rm LicenseReader.tar.003
rm LicenseReader.tar.004
echo $"Downloading and extracting license reader finished";

echo $"Cleaning license string to remove and unwanted characters - linebreaks, spaces, etc...";
LICENSEDATA=$(echo $LICENSEDATA|tr -d '\n')

echo $"Getting values from license started";
./LicenseReader "ExternalDnsUrl" $LICENSEDATA
./LicenseReader "ACRUserName" $LICENSEDATA
./LicenseReader "ACRUserPassword" $LICENSEDATA

#use whats in the license otherwise use whats passed in which is a generated hostname
EXTERNALDNSURLLICENSE=$(<ExternalDnsUrl.txt)
if [ "$EXTERNALDNSURLLICENSE" = "" ]; then
	echo $"EXTERNALDNSURLLICENSE is empty"
else	
	echo $"EXTERNALDNSURLLICENSE is not empty"
	EXTERNALDNSURL=$EXTERNALDNSURLLICENSE
	EXTERNALDNSNAME=$(echo $EXTERNALDNSURL | sed 's~http[s]*://~~g')
	DNSHOSTNAME=$(echo "${EXTERNALDNSNAME%%.*}")	
fi
echo $"EXTERNALDNSURL is $EXTERNALDNSURL";
echo $"EXTERNALDNSNAME is $EXTERNALDNSNAME";
echo $"DNSHOSTNAME is $DNSHOSTNAME";

#If acr info is passed in (via legacy script) use it, otherwise pull it from license
if [ "$ACRUSER" = "" ]; then
	echo $"ACR info was not passed in, values in license are being used."
	ACRUSER=$(<ACRUserName.txt)
	ACRUSERPASSWORD=$(<ACRUserPassword.txt)
else
	echo $"ACR info that was passed in is being used."
fi
echo $"ACRUSER is $ACRUSER";
echo $"ACRUSERPASSWORD is $ACRUSERPASSWORD";

echo $"Getting values from license finished";

#install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3;
chmod 700 get_helm.sh;
./get_helm.sh;

#create profisee namespace
kubectl create namespace profisee

#download the settings.yaml
curl -fsSL -o Settings.yaml "$REPOURL/Azure-ARM/Settings.yaml";

#install keyvault drivers
if [ "$USEKEYVAULT" = "Yes" ]; then
	echo $"Installing keyvault csi driver - started"
	#Install the Secrets Store CSI driver and the Azure Key Vault provider for the driver
	helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
	helm install --namespace profisee csi-secrets-store-provider-azure csi-secrets-store-provider-azure/csi-secrets-store-provider-azure
	echo $"Installing keyvault csi driver - finished"

	echo $"Installing keyvault aad pod identity - started"
	#Install the Azure Active Directory (Azure AD) identity into AKS.
	helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
	helm install --namespace profisee pod-identity aad-pod-identity/aad-pod-identity
	echo $"Installing keyvault aad pod identity - finished"

	#Assign roles needed for kv
	echo $"Managing Identity configuration for KV access - started"
	az role assignment create --role "Managed Identity Operator" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$RESOURCEGROUPNAME
	az role assignment create --role "Managed Identity Operator" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME
	az role assignment create --role "Virtual Machine Contributor" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME

	#Create AD Identity, get clientid and principalid to assign the reader role to (next command)
	identityName="AKSKeyVaultUser"
	az identity create -g $AKSINFRARESOURCEGROUPNAME -n $identityName

	akskvidentityClientId=$(az identity show -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'clientId')
	akskvidentityClientId=$(echo "$akskvidentityClientId" | tr -d '"')
	akskvidentityClientResourceId=$(az identity show -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'id')
	akskvidentityClientResourceId=$(echo "$akskvidentityClientResourceId" | tr -d '"')
	principalId=$(az identity show -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'principalId')
	principalId=$(echo "$principalId" | tr -d '"')
    echo $principalId
	#KEYVAULT looks like this this /subscriptions/$SUBID/resourceGroups/$kvresourceGroup/providers/Microsoft.KeyVault/vaults/$kvname
	IFS='/' read -r -a kv <<< "$KEYVAULT" #splits the KEYVAULT on slashes and gets last one
	keyVaultName=${kv[-1]}
	keyVaultResourceGroup=${kv[4]}
	keyVaultSubscriptionId=${kv[2]}
	az role assignment create --role "Reader" --assignee $principalId --scope $KEYVAULT
	az keyvault set-policy -n $keyVaultName --secret-permissions get --spn $akskvidentityClientId
	az keyvault set-policy -n $keyVaultName --key-permissions get --spn $akskvidentityClientId
    echo $"Managing Identity configuration for KV access - finished"
fi

#install nginx
echo $"Installing nginx started";
helm repo add stable https://charts.helm.sh/stable;

#new going forward
#helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
#helm install --namespace profisee nginx ingress-nginx/ingress-nginx

#get profisee nginx settings
curl -fsSL -o nginxSettings.yaml "$REPOURL/Azure-ARM/nginxSettings.yaml";
helm uninstall --namespace profisee nginx

if [ "$USELETSENCRYPT" = "Yes" ]; then
	echo $"Installing nginx for Lets Encrypt and setting the dns name for its IP."
	helm install --namespace profisee nginx stable/nginx-ingress --values nginxSettings.yaml --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNSHOSTNAME;
else
	echo $"Installing nginx not for Lets Encrypt and not setting the dns name for its IP."
	helm install --namespace profisee nginx stable/nginx-ingress --values nginxSettings.yaml
fi

echo $"Installing nginx finished, sleeping for 30s to wait for its IP";

#wait for the ip to be available.  usually a few seconds
sleep 30;
#get ip for nginx
nginxip=$(kubectl --namespace profisee get services nginx-nginx-ingress-controller --output="jsonpath={.status.loadBalancer.ingress[0].ip}");

if [ -z "$nginxip" ]; then
	#try again
	echo $"nginx is not configure properly because the LB IP is null, trying again in 60 seconds";
    sleep 60;
	nginxip=$(kubectl --namespace profisee get services nginx-nginx-ingress-controller --output="jsonpath={.status.loadBalancer.ingress[0].ip}");
	if [ -z "$nginxip" ]; then
    	echo $"nginx is not configure properly because the LB IP is null.  Exiting with error";
		exit 1
	fi
fi
echo $"nginx LB IP is $nginxip";

#fix tls variables
echo $"fix tls variables started";
#cert
if [ "$CONFIGUREHTTPS" = "Yes" ]; then
	printf '%s\n' "$TLSCERT" | sed 's/- /-\n/g; s/ -/\n-/g' | sed '/CERTIFICATE/! s/ /\n/g' >> a.cert;
	sed -e 's/^/    /' a.cert > tls.cert;
else    
    echo '    NA' > tls.cert;
fi
rm -f a.cert

#key
if [ "$CONFIGUREHTTPS" = "Yes" ]; then
    printf '%s\n' "$TLSKEY" | sed 's/- /-\n/g; s/ -/\n-/g' | sed '/PRIVATE/! s/ /\n/g' >> a.key;
	sed -e 's/^/    /' a.key > tls.key;
else
	echo '    NA' > tls.key;	    
fi
rm -f a.key

#set dns
if [ "$UPDATEDNS" = "Yes" ]; then
	echo "Update DNS started";
	az network dns record-set a delete -g $DOMAINNAMERESOURCEGROUP -z $DNSDOMAINNAME -n $DNSHOSTNAME --yes;
	az network dns record-set a add-record -g $DOMAINNAMERESOURCEGROUP -z $DNSDOMAINNAME -n $DNSHOSTNAME -a $nginxip --ttl 5;
	echo "Update DNS finished";
fi
echo $"fix tls variables finished";

#install profisee platform
echo $"install profisee platform statrted";
#set profisee helm chart settings
auth="$(echo -n "$ACRUSER:$ACRUSERPASSWORD" | base64)"
sed -i -e 's/$ACRUSER/'"$ACRUSER"'/g' Settings.yaml
sed -i -e 's/$ACRPASSWORD/'"$ACRUSERPASSWORD"'/g' Settings.yaml
sed -i -e 's/$ACREMAIL/'"support@profisee.com"'/g' Settings.yaml
sed -i -e 's/$ACRAUTH/'"$auth"'/g' Settings.yaml
sed -e '/$TLSCERT/ {' -e 'r tls.cert' -e 'd' -e '}' -i Settings.yaml
sed -e '/$TLSKEY/ {' -e 'r tls.key' -e 'd' -e '}' -i Settings.yaml

rm -f tls.cert
rm -f tls.key

#create the azure app id (clientid)
azureAppReplyUrl="${EXTERNALDNSURL}/profisee/auth/signin-microsoft"
if [ "$UPDATEAAD" = "Yes" ]; then
	echo "Update AAD started";
	azureClientName="${RESOURCEGROUPNAME}_${CLUSTERNAME}";
	echo $"azureClientName is $azureClientName";
	echo $"azureAppReplyUrl is $azureAppReplyUrl";
	CLIENTID=$(az ad app create --display-name $azureClientName --reply-urls $azureAppReplyUrl --query 'appId');
	#clean client id - remove quotes
	CLIENTID=$(echo "$CLIENTID" | tr -d '"')
	echo $"CLIENTID is $CLIENTID";
	#add a Graph API permission of "Sign in and read user profile"
	az ad app permission add --id $CLIENTID --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
	az ad app permission grant --id $CLIENTID --api 00000003-0000-0000-c000-000000000000
	echo "Update AAD finished";
fi

#get storage account pw - if not supplied
if [ "$FILEREPOPASSWORD" = "" ]; then
	echo $"FILEREPOPASSWORD was not passed in, getting it from the storage acount."
	FILEREPOPASSWORD=$(az storage account keys list --resource-group $RESOURCEGROUPNAME --account-name $STORAGEACCOUNTNAME --query '[0].value');
	#clean file repo password - remove quotes
	FILEREPOPASSWORD=$(echo "$FILEREPOPASSWORD" | tr -d '"')
else
	echo $"FILEREPOPASSWORD was passed in, using it."
fi


#If creating a new sql database, create firewall rule for sql server - add outbound ip of aks cluster 
if [ "$SQLSERVERCREATENEW" = "Yes" ]; then
	echo "Adding firewall rule to sql started";
	#strip off .database.windows.net
	IFS='.' read -r -a sqlString <<< "$SQLNAME"
	sqlServerName=${sqlString[0],,}; #lowercase is the ,,
	OutIP=$(az network public-ip list -g $AKSINFRARESOURCEGROUPNAME --query "[0].ipAddress");
	#clean OutIP - remove quotes
	OutIP=$(echo "$OutIP" | tr -d '"')
	az sql server firewall-rule create --resource-group $RESOURCEGROUPNAME --server $sqlServerName --name "aks lb ip" --start-ip-address $OutIP --end-ip-address $OutIP
	echo "Adding firewall rule to sql finished";
fi


#storage vars
FILEREPOUSERNAME="Azure\\\\\\\\${STORAGEACCOUNTNAME}"
FILEREPOURL="\\\\\\\\\\\\\\\\${STORAGEACCOUNTNAME}.file.core.windows.net\\\\\\\\${STORAGEACCOUNTFILESHARENAME}"

#PROFISEEVERSION looks like this 2020R1.0
#The repo is Profisee + everything to the left of the .
#The label is everything to the right of the .

ACRREPONAME="profiseeplatform"; 
ACRREPOLABEL="${PROFISEEVERSION,,}"; #lowercase is the ,,

#set values in Settings.yaml
sed -i -e 's/$SQLNAME/'"$SQLNAME"'/g' Settings.yaml
sed -i -e 's/$SQLDBNAME/'"$SQLDBNAME"'/g' Settings.yaml
sed -i -e 's/$SQLUSERNAME/'"$SQLUSERNAME"'/g' Settings.yaml
sed -i -e 's/$SQLUSERPASSWORD/'"$SQLUSERPASSWORD"'/g' Settings.yaml
sed -i -e 's/$FILEREPOACCOUNTNAME/'"$STORAGEACCOUNTNAME"'/g' Settings.yaml
sed -i -e 's/$FILEREPOUSERNAME/'"$FILEREPOUSERNAME"'/g' Settings.yaml
sed -i -e 's~$FILEREPOPASSWORD~'"$FILEREPOPASSWORD"'~g' Settings.yaml
sed -i -e 's/$FILEREPOURL/'"$FILEREPOURL"'/g' Settings.yaml
sed -i -e 's/$FILEREPOSHARENAME/'"$STORAGEACCOUNTFILESHARENAME"'/g' Settings.yaml
sed -i -e 's~$OIDCURL~'"$OIDCURL"'~g' Settings.yaml
sed -i -e 's/$CLIENTID/'"$CLIENTID"'/g' Settings.yaml
sed -i -e 's/$OIDCCLIENTSECRET/'"$OIDCCLIENTSECRET"'/g' Settings.yaml
sed -i -e 's/$ADMINACCOUNTNAME/'"$ADMINACCOUNTNAME"'/g' Settings.yaml
sed -i -e 's~$EXTERNALDNSURL~'"$EXTERNALDNSURL"'~g' Settings.yaml
sed -i -e 's/$EXTERNALDNSNAME/'"$EXTERNALDNSNAME"'/g' Settings.yaml
sed -i -e 's~$LICENSEDATA~'"$LICENSEDATA"'~g' Settings.yaml
sed -i -e 's/$ACRREPONAME/'"$ACRREPONAME"'/g' Settings.yaml
sed -i -e 's/$ACRREPOLABEL/'"$ACRREPOLABEL"'/g' Settings.yaml
if [ "$USEKEYVAULT" = "Yes" ]; then
	sed -i -e 's/$USEKEYVAULT/'true'/g' Settings.yaml

	sed -i -e 's/$KEYVAULTIDENTITCLIENTID/'"$akskvidentityClientId"'/g' Settings.yaml
	sed -i -e 's~$KEYVAULTIDENTITYRESOURCEID~'"$akskvidentityClientResourceId"'~g' Settings.yaml

	sed -i -e 's/$SQL_USERNAMESECRET/'"$SQLUSERNAME"'/g' Settings.yaml
	sed -i -e 's/$SQL_USERPASSWORDSECRET/'"$SQLUSERPASSWORD"'/g' Settings.yaml
	sed -i -e 's/$TLS_CERTSECRET/'"$TLSCERT"'/g' Settings.yaml
	sed -i -e 's/$LICENSE_DATASECRET/'"$LICENSEDATASECRETNAME"'/g' Settings.yaml
	sed -i -e 's/$KUBERNETESCLIENTID/'"$KUBERNETESCLIENTID"'/g' Settings.yaml

	sed -i -e 's/$KEYVAULTNAME/'"$keyVaultName"'/g' Settings.yaml
	sed -i -e 's/$KEYVAULTRESOURCEGROUP/'"$keyVaultResourceGroup"'/g' Settings.yaml

	sed -i -e 's/$AZURESUBSCRIPTIONID/'"$keyVaultSubscriptionId"'/g' Settings.yaml
	sed -i -e 's/$AZURETENANTID/'"$TENANTID"'/g' Settings.yaml

	$SUBSCRIPTIONID
else
	sed -i -e 's/$USEKEYVAULT/'false'/g' Settings.yaml
fi

if [ "$USELETSENCRYPT" = "Yes" ]; then
	#################################Lets Encrypt Part 1 Start #####################################
	# Label the ingress-basic namespace to disable resource validation
	echo "Lets Encrypt Part 1 started";
	kubectl label namespace default cert-manager.io/disable-validation=true
	helm repo add jetstack https://charts.jetstack.io
	# Update your local Helm chart repository cache
	helm repo update
	# Install the cert-manager Helm chart
	helm install --namespace profisee cert-manager jetstack/cert-manager --namespace default --version v0.16.1 --set installCRDs=true --set nodeSelector."beta\.kubernetes\.io/os"=linux --set webhook.nodeSelector."beta\.kubernetes\.io/os"=linux --set cainjector.nodeSelector."beta\.kubernetes\.io/os"=linux
	#wait for the cert manager to be ready
	echo $"Lets Encrypt, waiting for certificate manager to be ready, sleeping for 30s";
	sleep 30;
	#create the CA cluster issuer - now in profisee helm chart
	#curl -fsSL -o clusterissuer.yaml "$REPOURL/Azure-ARM/clusterissuer.yaml";
	#kubectl apply -f clusterissuer.yaml
	sed -i -e 's/$USELETSENCRYPT/'true'/g' Settings.yaml
	echo "Lets Encrypt Part 1 finshed";
	#################################Lets Encrypt Part 1 End #######################################
else
	sed -i -e 's/$USELETSENCRYPT/'false'/g' Settings.yaml
fi

#Add settings.yaml as a secret so its always available after the deployment
kubectl delete secret profisee-settings --namespace profisee
kubectl create secret generic profisee-settings --namespace profisee --from-file=Settings.yaml

#################################Install Profisee Start #######################################
echo "Install Profisee started";
helm repo add profisee $HELMREPOURL
helm repo update
helm uninstall --namespace profisee profiseeplatform
helm install --namespace profisee profiseeplatform profisee/profisee-platform --values Settings.yaml

#Make sure it installed, if not return error
profiseeinstalledname=$(echo $(helm list --filter 'profisee+' --namespace profisee -o json)| jq '.[].name')
if [ -z "$profiseeinstalledname" ]; then
	echo "Profisee did not get installed.  Exiting with error";
	exit 1
else
	echo "Install Profisee finished";
fi;
#################################Install Profisee End #######################################

#wait for pod to be ready (downloaded)
echo "Waiting for pod to be downloaded and be ready..";
sleep 30;
kubectl wait --timeout=1200s --for=condition=ready pod/profisee-0 --namespace profisee

echo $"Install Profisee Platform finished";

result="{\"Result\":[\
{\"IP\":\"$nginxip\"},\
{\"WEBURL\":\"${EXTERNALDNSURL}/Profisee\"},\
{\"FILEREPOUSERNAME\":\"$FILEREPOUSERNAME\"},\
{\"FILEREPOURL\":\"$FILEREPOURL\"},\
{\"AZUREAPPCLIENTID\":\"$CLIENTID\"},\
{\"AZUREAPPREPLYURL\":\"$azureAppReplyUrl\"},\
{\"SQLSERVER\":\"$SQLNAME\"},\
{\"SQLDATABASE\":\"$SQLDBNAME\"},\
{\"ACRREPONAME\":\"$ACRREPONAME\"},\
{\"ACRREPOLABEL\":\"$ACRREPOLABEL\"}\
]}"
echo $result > $AZ_SCRIPTS_OUTPUT_PATH
