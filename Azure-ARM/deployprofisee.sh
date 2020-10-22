#!/bin/bash
REPOURL="https://raw.githubusercontent.com/profisee/kubernetes/master";

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

#install nginx
echo $"Installing nginx started";
helm repo add stable https://kubernetes-charts.storage.googleapis.com/;
#get profisee nginx settings
curl -fsSL -o nginxSettings.yaml "$REPOURL/Azure-ARM/nginxSettings.yaml";
helm uninstall nginx

if [ "$USELETSENCRYPT" = "Yes" ]; then
	echo $"Installing nginx for Lets Encrypt and setting the dns name for its IP."
	helm install nginx stable/nginx-ingress --values nginxSettings.yaml --set controller.service.loadBalancerIP=$publicInIP --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNSHOSTNAME;
else
	echo $"Installing nginx not for Lets Encrypt and not setting the dns name for its IP."
	helm install nginx stable/nginx-ingress --values nginxSettings.yaml --set controller.service.loadBalancerIP=$publicInIP	
fi

echo $"Installing nginx finished";

#wait for the ip to be available.  usually a few seconds
sleep 30;
#get ip for nginx
nginxip=$(kubectl get services nginx-nginx-ingress-controller --output="jsonpath={.status.loadBalancer.ingress[0].ip}");
echo $"nginx LB IP is $nginxip";

#fix tls variables
echo $"fix tls variables started\n";
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
echo $"fix tls variables finished\n";

#install profisee platform
echo $"install profisee platform statrted";
#set profisee helm chart settings
curl -fsSL -o Settings.yaml "$REPOURL/Azure-ARM/Settings.yaml";
auth="$(echo -n "$ACRUSER:$ACRUSERPASSWORD" | base64)"
sed -i -e 's/$ACRUSER/'"$ACRUSER"'/g' Settings.yaml
sed -i -e 's/$ACRPASSWORD/'"$ACRUSERPASSWORD"'/g' Settings.yaml
sed -i -e 's/$ACREMAIL/'"support@profisee.com"'/g' Settings.yaml
sed -i -e 's/$ACRAUTH/'"$auth"'/g' Settings.yaml
sed -e '/$TLSCERT/ {' -e 'r tls.cert' -e 'd' -e '}' -i Settings.yaml
sed -e '/$TLSKEY/ {' -e 'r tls.key' -e 'd' -e '}' -i Settings.yaml

rm tls.cert
rm tls.key

#create the azure app id (clientid)
azureAppReplyUrl="${EXTERNALDNSURL}/profisee/auth/signin-microsoft"
if [ "$UPDATEAAD" = "Yes" ]; then
	echo "Update AAD started";
	azureClientName="${RESOURCEGROUPNAME}_${CLUSTERNAME}";
	CLIENTID=$(az ad app create --display-name $azureClientName --reply-urls $azureAppReplyUrl --query 'appId');
	#clean client id - remove quotes
	CLIENTID=$(echo "$CLIENTID" | tr -d '"')
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
sed -i -e 's/$FILEREPOUSERNAME/'"$FILEREPOUSERNAME"'/g' Settings.yaml
sed -i -e 's~$FILEREPOPASSWORD~'"$FILEREPOPASSWORD"'~g' Settings.yaml
sed -i -e 's/$FILEREPOURL/'"$FILEREPOURL"'/g' Settings.yaml
sed -i -e 's/$FILESHARENAME/'"$STORAGEACCOUNTFILESHARENAME"'/g' Settings.yaml
sed -i -e 's~$OIDCURL~'"$OIDCURL"'~g' Settings.yaml
sed -i -e 's/$CLIENTID/'"$CLIENTID"'/g' Settings.yaml
sed -i -e 's/$OIDCCLIENTSECRET/'"$OIDCCLIENTSECRET"'/g' Settings.yaml
sed -i -e 's/$ADMINACCOUNTNAME/'"$ADMINACCOUNTNAME"'/g' Settings.yaml
sed -i -e 's~$EXTERNALDNSURL~'"$EXTERNALDNSURL"'~g' Settings.yaml
sed -i -e 's/$EXTERNALDNSNAME/'"$EXTERNALDNSNAME"'/g' Settings.yaml
sed -i -e 's~$LICENSEDATA~'"$LICENSEDATA"'~g' Settings.yaml
sed -i -e 's/$ACRREPONAME/'"$ACRREPONAME"'/g' Settings.yaml
sed -i -e 's/$ACRREPOLABEL/'"$ACRREPOLABEL"'/g' Settings.yaml

#Add settings.yaml as a secret so its always available after the deployment
kubectl delete secret profisee-settings
kubectl create secret generic profisee-settings --from-file=Settings.yaml

if [ "$USELETSENCRYPT" = "Yes" ]; then
	#################################Lets Encrypt Part 1 Start #####################################
	# Label the ingress-basic namespace to disable resource validation
	echo "Lets Encrypt Part 1 started";
	kubectl label namespace default cert-manager.io/disable-validation=true
	helm repo add jetstack https://charts.jetstack.io
	# Update your local Helm chart repository cache
	helm repo update
	# Install the cert-manager Helm chart
	helm install cert-manager jetstack/cert-manager --namespace default --version v0.16.1 --set installCRDs=true --set nodeSelector."beta\.kubernetes\.io/os"=linux --set webhook.nodeSelector."beta\.kubernetes\.io/os"=linux --set cainjector.nodeSelector."beta\.kubernetes\.io/os"=linux
	#wait for the cert manager to be ready
	sleep 30;
	#create the CA cluster issuer
	curl -fsSL -o clusterissuer.yaml "$REPOURL/Azure-ARM/clusterissuer.yaml";
	kubectl apply -f clusterissuer.yaml
	echo "Lets Encrypt Part 1 finshed";
	#################################Lets Encrypt Part 1 End #######################################
fi

#################################Install Profisee Start #######################################
echo "Install Profisee started";
helm repo add profisee https://profiseedev.github.io/kubernetes
helm repo update
helm uninstall profiseeplatform
helm install profiseeplatform profisee/profisee-platform --values Settings.yaml
echo "Install Profisee finsihed";
#################################Install Profisee End #######################################
#################################Add Azure File volume Start #######################################
echo "Add Azure File volume started";
curl -fsSL -o StatefullSet_AddAzureFileVolume.yaml "$REPOURL/Azure-ARM/StatefullSet_AddAzureFileVolume.yaml";
STORAGEACCOUNTNAME="$(echo -n "$STORAGEACCOUNTNAME" | base64)"
FILEREPOPASSWORD="$(echo -n "$FILEREPOPASSWORD" | base64 | tr -d '\n')" #The last tr is needed because base64 inserts line breaks after every 76th character
sed -i -e 's/$STORAGEACCOUNTNAME/'"$STORAGEACCOUNTNAME"'/g' StatefullSet_AddAzureFileVolume.yaml
sed -i -e 's/$STORAGEACCOUNTKEY/'"$FILEREPOPASSWORD"'/g' StatefullSet_AddAzureFileVolume.yaml
sed -i -e 's/$STORAGEACCOUNTFILESHARENAME/'"$STORAGEACCOUNTFILESHARENAME"'/g' StatefullSet_AddAzureFileVolume.yaml
kubectl apply -f StatefullSet_AddAzureFileVolume.yaml
echo "Add Azure File volume finished";
#################################Add Azure File volume End #######################################

if [ "$USELETSENCRYPT" = "Yes" ]; then
	#################################Lets Encrypt Part 2 Start #####################################
	#Install Ingress for lets encrypt
	echo "Lets Encrypt Part 2 started";
	curl -fsSL -o ingressletsencrypt.yaml "$REPOURL/Azure-ARM/ingressletsencrypt.yaml";
	sed -i -e 's/$EXTERNALDNSNAME/'"$EXTERNALDNSNAME"'/g' ingressletsencrypt.yaml
	kubectl apply -f ingressletsencrypt.yaml
	echo "Lets Encrypt Part 2 finished";
	#################################Lets Encrypt Part 2 End #######################################
fi

echo $"install profisee platform finished";
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
