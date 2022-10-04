#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
logfile=log_$(date +%Y-%m-%d_%H-%M-%S).out
exec 1>$logfile 2>&1

echo $"Profisee deploymented started $(date +"%Y-%m-%d %T")";


FILE=./get_helm.sh
if [ -f "$FILE" ]; then
    echo $"Profisee deploymented exiting, already has been ran";
	exit 1;
fi

REPONAME="profisee"
REPOURL="https://raw.githubusercontent.com/$REPONAME/kubernetes/master";
HELMREPOURL="https://$REPONAME.github.io/kubernetes";
echo $"REPOURL is $REPOURL";
echo $"HELMREPOURL is $HELMREPOURL";

if [ -z "$RESOURCEGROUPNAME" ]; then
	RESOURCEGROUPNAME=$ResourceGroupName
fi

if [ -z "$SUBSCRIPTIONID" ]; then
	SUBSCRIPTIONID=$SubscriptionId
fi

printenv;

#az login --identity

#Get AKS credentials, this allows us to use kubectl commands, if needed.
az aks get-credentials --resource-group $RESOURCEGROUPNAME --name $CLUSTERNAME --overwrite-existing;

#Install dotnet core.
echo $"Installation of dotnet core started.";
curl -fsSL -o dotnet-install.sh https://dot.net/v1/dotnet-install.sh
#Set permisssions for installation script.
chmod 755 ./dotnet-install.sh
#Install dotnet.
./dotnet-install.sh -c Current
echo $"Installation of dotnet core finished.";

#Downloadind and extracting Proisee license reader.
echo $"Download and extraction of Profisee license reader started.";
curl -fsSL -o LicenseReader.tar.001 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.001"
curl -fsSL -o LicenseReader.tar.002 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.002"
curl -fsSL -o LicenseReader.tar.003 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.003"
curl -fsSL -o LicenseReader.tar.004 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.004"
cat LicenseReader.tar.* | tar xf -
rm LicenseReader.tar.001
rm LicenseReader.tar.002
rm LicenseReader.tar.003
rm LicenseReader.tar.004
echo $"Download and extraction of Profisee license reader finished.";

echo $"Clean Profisee license string of any unwanted characters such as linebreaks, spaces, etc...";
LICENSEDATA=$(echo $LICENSEDATA|tr -d '\n')

echo $"Search Profisee license for the fully qualified domain name value...";
EXTERNALDNSURLLICENSE=$(./LicenseReader "ExternalDnsUrl" $LICENSEDATA)

#Use FQDN that is in license, otherwise use the Azure generated FQDN.
#EXTERNALDNSURLLICENSE=$(<ExternalDnsUrl.txt)
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

#If ACR credentials are passed in via legacy script, use those. Otherwise, pull ACR credentials from license.
if [ "$ACRUSER" = "" ]; then
	echo $"ACR credentials were not passed in, will use values from license."
	#ACRUSER=$(<ACRUserName.txt)
	#ACRUSERPASSWORD=$(<ACRUserPassword.txt)
	ACRUSER=$(./LicenseReader "ACRUserName" $LICENSEDATA)
    ACRUSERPASSWORD=$(./LicenseReader "ACRUserPassword" $LICENSEDATA)
else
	echo $"Using ACR credentials that were passed in."
fi
echo $"ACRUSER is $ACRUSER";
echo $"ACRUSERPASSWORD is $ACRUSERPASSWORD";

echo $"Finished parsing values from Profisee license.";

#Install Helm
echo $"Installation of Helm started.";
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3;
chmod 700 get_helm.sh;
./get_helm.sh;
echo $"Installation of Helm finished.";

#Install kubectl
echo $"Installation of kubectl started.";
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
echo $"Installation of kubectl finished.";

#Create profisee namespace in AKS cluster.
echo $"Creation of profisee namespace in cluster started. If present, we skip creation and use it.";

#If namespace exists, skip creating it.
namespacepresent=$(kubectl get namespace -o jsonpath='{.items[?(@.metadata.name=="profisee")].metadata.name}')
if [ "$namespacepresent" = "profisee" ]; then
	echo $"Namespace is already created, continuing."
else
	kubectl create namespace profisee
fi
echo $"Creation of profisee namespace in cluster finished.";

#Download Settings.yaml file from Profisee repo.
curl -fsSL -o Settings.yaml "$REPOURL/Azure-ARM/Settings.yaml";

#Installation of Key Vault Container Storage Interface (CSI) driver started.
if [ "$USEKEYVAULT" = "Yes" ]; then
	echo $"Installation of Key Vault Container Storage Interface (CSI) driver started. If present, we uninstall and reinstall it."
	#Install the Secrets Store CSI driver and the Azure Key Vault provider for the driver
	helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
	
	#If Key Vault CSI driver is present, uninstall it.
        kvcsipresent=$(helm list -n profisee -f csi-secrets-store-provider-azure -o table --short)
        if [ "$kvcsipresent" = "csi-secrets-store-provider-azure" ]; then
	        helm uninstall -n profisee csi-secrets-store-provider-azure;
	        echo $"Will sleep for 30 seconds to allow clean uninstall of Key Vault CSI driver."
	        sleep 30;
        fi
	
	#https://github.com/Azure/secrets-store-csi-driver-provider-azure/releases/tag/0.0.16
	#The behavior changed so now you have to enable the secrets-store-csi-driver.syncSecret.enabled=true
	#We are not but if this is to run on a windows node, then you use this --set windows.enabled=true --set secrets-store-csi-driver.windows.enabled=true
	helm install -n profisee csi-secrets-store-provider-azure csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --set secrets-store-csi-driver.syncSecret.enabled=true
	echo $"Installation of Key Vault Container Storage Interface (CSI) driver finished."
	
	
	#Install AAD pod identity into AKS.
	echo $"Installation of Key Vault Azure Active Directory Pod Identity driver started. If present, we uninstall and reinstall it."
	#If AAD Pod Identity is present, uninstall it.
        aadpodpresent=$(helm list -n profisee -f pod-identity -o table --short)
        if [ "$aadpodpresent" = "pod-identity" ]; then
	        helm uninstall -n profisee pod-identity;
	        echo $"Will sleep for 30 seconds to allow clean uninstall of AAD Pod Identity."
	        sleep 30;
        fi
	
	helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
	helm install -n profisee pod-identity aad-pod-identity/aad-pod-identity
	echo $"Installation of Key Vault Azure Active Directory Pod Identity driver finished."

	#Assign AAD roles to the AKS AgentPool Managed Identity. The Pod identity communicates with the AgentPool MI, which in turn communicates with the Key Vault specific Managed Identity.
	echo $"AKS Managed Identity configuration for Key Vault access started."

	echo $"AKS AgentPool Managed Identity configuration for Key Vault access step 1 started."
	echo "Running az role assignment create --role "Managed Identity Operator" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$RESOURCEGROUPNAME"
	az role assignment create --role "Managed Identity Operator" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$RESOURCEGROUPNAME
	echo "Running az role assignment create --role "Managed Identity Operator" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME"
	az role assignment create --role "Managed Identity Operator" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME
	echo "Running az role assignment create --role "Virtual Machine Contributor" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME"
	az role assignment create --role "Virtual Machine Contributor" --assignee $KUBERNETESCLIENTID --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME
	echo $"AKS AgentPool Managed Identity configuration for Key Vault access step 1 finished."

	#Create Azure AD Managed Identity specifically for Key Vault, get its ClientiId and PrincipalId so we can assign to it the Reader role in steps 3a, 3b and 3c to.
	echo $"Key Vault Specific Managed Identity configuration for Key Vault access step 2 started."
	identityName="AKSKeyVaultUser"
	akskvidentityClientId=$(az identity create -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'clientId' -o tsv);
	akskvidentityClientResourceId=$(az identity show -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'id' -o tsv)
	principalId=$(az identity show -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'principalId' -o tsv)
	echo $"Key VAult Specific Managed  Identity configuration for Key Vault access step 2 finished."

	echo $"Key Vault Specific Managed Identity configuration for KV access step 3 started."
	echo "Sleeping for 60 seconds to wait for MI to be ready"
	sleep 60;
	#KEYVAULT looks like this this /subscriptions/$SUBID/resourceGroups/$kvresourceGroup/providers/Microsoft.KeyVault/vaults/$kvname
	IFS='/' read -r -a kv <<< "$KEYVAULT" #splits the KEYVAULT on slashes and gets last one
	keyVaultName=${kv[-1]}
	keyVaultResourceGroup=${kv[4]}
	keyVaultSubscriptionId=${kv[2]}
	echo $"KEYVAULT is $KEYVAULT"
	echo $"keyVaultName is $keyVaultName"
	echo $"akskvidentityClientId is $akskvidentityClientId"
	echo $"principalId is $principalId"
    
    #Check if Key Vault is RBAC or policy based.
    echo $"Checking if Key Vauls is RBAC based or policy based"
    rbacEnabled=$(az keyvault show --name $keyVaultName --subscription $keyVaultSubscriptionId --query "properties.enableRbacAuthorization")

    #If Key Vault is RBAC based, assign Key Vault Secrets User role to the Key Vault Specific Managed Identity, otherwise assign Get policies for Keys, Secrets and Certificates.
    if [ "$rbacEnabled" = true ]; then
		echo $"Setting Key Vault Secrets User RBAC role to the Key Vault Specific Managed Idenity."
		echo "Running az role assignment create --role 'Key Vault Secrets User' --assignee $principalId --scope $KEYVAULT"
		az role assignment create --role "Key Vault Secrets User" --assignee $principalId --scope $KEYVAULT
	else
		echo $"Setting Key Vault access policies to the Key Vault Specific Managed Identity."
		echo $"Key Vault Specific Managed Identity configuration for KV access step 3a started. Assigning Get access policy for secrets."
		echo "Running az keyvault set-policy -n $keyVaultName --subscription $keyVaultSubscriptionId --secret-permissions get --object-id $principalId --query id"
		az keyvault set-policy -n $keyVaultName --subscription $keyVaultSubscriptionId --secret-permissions get --object-id $principalId --query id
		echo $"Key Vault Specific Managed Identity configuration for KV access step 3a finished. Assignment completed."

		echo $"Key Vault Specific Managed Identity configuration for KV access step 3b started. Assigning Get access policy for keys."
		echo "Running az keyvault set-policy -n $keyVaultName --subscription $keyVaultSubscriptionId --key-permissions get --object-id $principalId --query id"
		az keyvault set-policy -n $keyVaultName --subscription $keyVaultSubscriptionId --key-permissions get --object-id $principalId --query id
		echo $"Key Vault Specific Managed Identity configuration for KV access step 3b finished. Assignment completed."

		echo $"Key Vault Specific Managed Identity configuration for KV access step 3c started. Assigning Get access policy for certificates."
		echo "Running az keyvault set-policy -n $keyVaultName --subscription $keyVaultSubscriptionId --certificate-permissions get --object-id $principalId --query id"
		az keyvault set-policy -n $keyVaultName --subscription $keyVaultSubscriptionId --certificate-permissions get --object-id $principalId --query id
		echo $"Key Vault Specific Managed Identity configuration for KV access step 3c finished. Assignment completed."

		echo $"Key Vault Specific Managed Identity setup is now finished."
	fi
	
fi

#Installation of nginx
echo $"Installation of nginx ingress started.";
echo $"Adding ingress-nginx repo."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

#Get profisee nginx settings
echo $"Acquiring nginxSettings.yaml file from Profisee repo."
curl -fsSL -o nginxSettings.yaml "$REPOURL/Azure-ARM/nginxSettings.yaml";

#If nginx is present, uninstall it.
echo "If nginx is installed, we'll uninstall it first."
nginxpresent=$(helm list -n profisee -f nginx -o table --short)
if [ "$nginxpresent" = "nginx" ]; then
	helm uninstall -n profisee nginx;
	echo $"Will sleep for a minute to allow clean uninstall of nginx."
	sleep 60;
fi

#Install nginx either with or without Let's Encrypt
echo $"Installation of nginx started.";
if [ "$USELETSENCRYPT" = "Yes" ]; then
	echo $"Install nginx ready to integrate with Let's Encrypt's automatic certificate provisioning and renewal, and set the DNS FQDN to the load balancer's ingress public IP address."
	helm install -n profisee nginx ingress-nginx/ingress-nginx --values nginxSettings.yaml --set controller.service.loadBalancerIP=$nginxip --set controller.service.appProtocol=false --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNSHOSTNAME;
else
	echo $"Install nginx without integration with Let's Encrypt's automatic certificate provisioning and renewal, also do not set the DNS FQDN to the load balancer's ingress public IP address."
	helm install -n profisee nginx ingress-nginx/ingress-nginx --values nginxSettings.yaml --set controller.service.loadBalancerIP=$nginxip --set controller.service.appProtocol=false
fi

echo $"Installation of nginx finished, sleeping for 30 seconds to wait for the load balancer's public IP to become available.";
sleep 30;

#Get the load balancer's public IP so it can be used later on.
echo $"Let's see if the the load balancer's IP address is available."
nginxip=$(kubectl -n profisee get services nginx-ingress-nginx-controller --output="jsonpath={.status.loadBalancer.ingress[0].ip}");
#
if [ -z "$nginxip" ]; then
	#try again
	echo $"Nginx is not configured properly because the load balancer's public IP is null, will wait for another minute.";
    sleep 60;
	nginxip=$(kubectl -n profisee get services nginx-ingress-nginx-controller --output="jsonpath={.status.loadBalancer.ingress[0].ip}");
	if [ -z "$nginxip" ]; then
    	echo $"Nginx is not configured properly because the load balancer's public IP is null. Exiting with error.";
		exit 1
	fi
fi
echo $"The load balancer's public IP is $nginxip";

#Fix the TLS variables
echo $"Correction of TLS variables started.";
#This is for the certificate
if [ "$CONFIGUREHTTPS" = "Yes" ]; then
	printf '%s\n' "$TLSCERT" | sed 's/- /-\n/g; s/ -/\n-/g' | sed '/CERTIFICATE/! s/ /\n/g' >> a.cert;
	sed -e 's/^/    /' a.cert > tls.cert;
else    
    echo '    NA' > tls.cert;
fi
rm -f a.cert

#This is for the key
if [ "$CONFIGUREHTTPS" = "Yes" ]; then
    printf '%s\n' "$TLSKEY" | sed 's/- /-\n/g; s/ -/\n-/g' | sed '/PRIVATE/! s/ /\n/g' >> a.key;
	sed -e 's/^/    /' a.key > tls.key;
else
	echo '    NA' > tls.key;	    
fi
rm -f a.key

#Set the DNS record in the DNS zone. If present, remove it.
if [ "$UPDATEDNS" = "Yes" ]; then
	echo "Update of DNS record started.";
	echo "Deletion of existing A record started.";
	az network dns record-set a delete -g $DOMAINNAMERESOURCEGROUP -z $DNSDOMAINNAME -n $DNSHOSTNAME --yes;
	echo "Deletion of existing A record finished."
	echo "Creation of new A record started.";
	az network dns record-set a add-record -g $DOMAINNAMERESOURCEGROUP -z $DNSDOMAINNAME -n $DNSHOSTNAME -a $nginxip --ttl 5;
	echo "Creation of new A record finished.";
	echo "Update of DNS record finished.";
fi
echo $"Correction of TLS variables finished.";

#Installation of Profisee platform
echo $"Installation of Profisee platform statrted.";
#Configure Profisee helm chart settings
auth="$(echo -n "$ACRUSER:$ACRUSERPASSWORD" | base64)"
sed -i -e 's/$ACRUSER/'"$ACRUSER"'/g' Settings.yaml
sed -i -e 's/$ACRPASSWORD/'"$ACRUSERPASSWORD"'/g' Settings.yaml
sed -i -e 's/$ACREMAIL/'"support@profisee.com"'/g' Settings.yaml
sed -i -e 's/$ACRAUTH/'"$auth"'/g' Settings.yaml
sed -e '/$TLSCERT/ {' -e 'r tls.cert' -e 'd' -e '}' -i Settings.yaml
sed -e '/$TLSKEY/ {' -e 'r tls.key' -e 'd' -e '}' -i Settings.yaml

rm -f tls.cert
rm -f tls.key

echo $"WEBAPPNAME is $WEBAPPNAME";
WEBAPPNAME="${WEBAPPNAME,,}"
echo $"WEBAPPNAME is now lower $WEBAPPNAME";

#Create the Azure app id (clientid)
azureAppReplyUrl="${EXTERNALDNSURL}/${WEBAPPNAME}/auth/signin-microsoft"
if [ "$UPDATEAAD" = "Yes" ]; then
	echo "Update of Azure Active Directory started. Now we will create the Azure AD Application registration.";
	azureClientName="${RESOURCEGROUPNAME}_${CLUSTERNAME}";
	echo $"azureClientName is $azureClientName";
	echo $"azureAppReplyUrl is $azureAppReplyUrl";

	echo "Creation of the Azure Active Directory application registration started."
	CLIENTID=$(az ad app create --display-name $azureClientName --reply-urls $azureAppReplyUrl --query 'appId' -o tsv);
	echo $"CLIENTID is $CLIENTID";
	if [ -z "$CLIENTID" ]; then
		echo $"CLIENTID is null fetching";
		CLIENTID=$(az ad app list --display-name $azureClientName --query [0].appId -o tsv)
		echo $"CLIENTID is $CLIENTID";
	fi
	echo "Creation of the Azure Active Directory application registration finished."
	echo "Sleeping for 20 seconds to wait for the app registration to be ready."
	sleep 20;

	#If Azure Application Registration User.Read permission is present, skip adding it.
	echo $"Let's check to see if the User.Read permission is granted, skip if has been."
        appregpermissionspresent=$(az ad app permission list --id $CLIENTID --query "[].resourceAccess[].id" -o tsv)
        if [ "$appregpermissionspresent" = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" ]; then
	        echo $"User.Read permissions already present, no need to add it."
	else
	
	        echo "Update of the application registration's permissions, step 1 started."
	        #Add a Graph API permission to "Sign in and read user profile"
	        az ad app permission add --id $CLIENTID --api 00000003-0000-0000-c000-000000000000 --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
	        echo "Creation of the service principal started."
	        az ad sp create --id $CLIENTID
	        echo "Creation of the service principal finished."
	        echo "Update of the application registration's permissions, step 1 finished."

	        echo "Update of the application registration's permissions, step 2 started."
	        az ad app permission grant --id $CLIENTID --api 00000003-0000-0000-c000-000000000000
	        echo "Update of the application registration's permissions, step 2 finished."
	        echo "Update of Azure Active Directory finished.";
	fi
fi

#If not supplied, acquire storage account credentials.
if [ "$FILEREPOPASSWORD" = "" ]; then
	echo $"FILEREPOPASSWORD was not passed in, acquiring credentials from the storage account."
	FILEREPOPASSWORD=$(az storage account keys list --resource-group $RESOURCEGROUPNAME --account-name $STORAGEACCOUNTNAME --query '[0].value');
	#clean file repo password - remove quotes
	FILEREPOPASSWORD=$(echo "$FILEREPOPASSWORD" | tr -d '"')
else
	echo $"FILEREPOPASSWORD was passed in, we'll use it."
fi


#If deployment of a new SQL database has been selected, we will create a SQL firewall rule to allow traffic from the AKS cluster's egress IP. 
if [ "$SQLSERVERCREATENEW" = "Yes" ]; then
	echo "Addition of a SQL firewall rule started.";
	#strip off .database.windows.net
	IFS='.' read -r -a sqlString <<< "$SQLNAME"
	echo "SQLNAME is $SQLNAME"
	sqlServerName=${sqlString[0],,}; #lowercase is the ,,
	echo "sqlServerName is $sqlServerName"

	echo "Acquiring the IP address from  $AKSINFRARESOURCEGROUPNAME"
	OutIP=$(az network public-ip list -g $AKSINFRARESOURCEGROUPNAME --query "[0].ipAddress" -o tsv);
	echo "The load balancer's egress public IP is $OutIP"
	az sql server firewall-rule create --resource-group $RESOURCEGROUPNAME --server $sqlServerName --name "aks lb ip" --start-ip-address $OutIP --end-ip-address $OutIP
	echo "Addition of the SQL firewall rule finished.";
fi

echo "The variables will now be set in the Settings.yaml file"
#Setting storage related variables
FILEREPOUSERNAME="Azure\\\\\\\\${STORAGEACCOUNTNAME}"
FILEREPOURL="\\\\\\\\\\\\\\\\${STORAGEACCOUNTNAME}.file.core.windows.net\\\\\\\\${STORAGEACCOUNTFILESHARENAME}"

#PROFISEEVERSION looks like this profiseeplatform:2022R1.0
#The repository name is profiseeplatform, it is everything to the left of the colon sign :
#The label is everything to the right of the :

IFS=':' read -r -a repostring <<< "$PROFISEEVERSION"

#lowercase is the ,,
ACRREPONAME="${repostring[0],,}"; 
ACRREPOLABEL="${repostring[1],,}"

#Setting values in the Settings.yaml
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
sed -i -e 's~$PURVIEWURL~'"$PURVIEWURL"'~g' Settings.yaml
sed -i -e 's/$PURVIEWTENANTID/'"$TENANTID"'/g' Settings.yaml
sed -i -e 's/$PURVIEWCLIENTID/'"$PURVIEWCLIENTID"'/g' Settings.yaml
sed -i -e 's/$PURVIEWCLIENTSECRET/'"$PURVIEWCLIENTSECRET"'/g' Settings.yaml
sed -i -e 's/$WEBAPPNAME/'"$WEBAPPNAME"'/g' Settings.yaml
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

else
	sed -i -e 's/$USEKEYVAULT/'false'/g' Settings.yaml
fi

if [ "$USELETSENCRYPT" = "Yes" ]; then
	#################################Lets Encrypt Start #####################################
	# Label the namespace to disable resource validation
	echo "Let's Encrypt installation started";
	kubectl label namespace profisee cert-manager.io/disable-validation=true
	helm repo add jetstack https://charts.jetstack.io
	# Update your local Helm chart repository cache
	helm repo update
	#If cert-manager is present, uninstall it.
        certmgrpresent=$(helm list -n profisee -f cert-manager -o table --short)
        if [ "$certmgrpresent" = "cert-manager" ]; then
	        helm uninstall -n profisee cert-manager;
	        echo $"Will sleep for 20 seconds to allow clean uninstall of cert-manager."
	        sleep 20;
        fi
	# Install the cert-manager Helm chart
	helm install cert-manager jetstack/cert-manager -n profisee --set installCRDs=true --set nodeSelector."kubernetes\.io/os"=linux --set webhook.nodeSelector."kubernetes\.io/os"=linux --set cainjector.nodeSelector."kubernetes\.io/os"=linux --set startupapicheck.nodeSelector."kubernetes\.io/os"=linux
	# Wait for the cert manager to be ready
	echo $"Let's Encrypt is waiting for certificate manager to be ready, sleeping for 30 seconds.";
	sleep 30;
	sed -i -e 's/$USELETSENCRYPT/'true'/g' Settings.yaml
	echo "Let's Encrypt installation finshed";
	#################################Lets Encrypt End #######################################
else
	sed -i -e 's/$USELETSENCRYPT/'false'/g' Settings.yaml
fi

#Adding Settings.yaml as a secret generated only from the initial deployment of Profisee. Future updates, such as license changes via the profisee-license secret, or SQL credentials updates via the profisee-sql-password secret, will NOT be reflected in this secret. Proceed with caution!
kubectl delete secret profisee-settings -n profisee --ignore-not-found
kubectl create secret generic profisee-settings -n profisee --from-file=Settings.yaml

#################################Install Profisee Start #######################################
echo "Installation of Profisee platform started $(date +"%Y-%m-%d %T")";
helm repo add profisee $HELMREPOURL
helm repo update

#If Profisee is present, uninstall it. If not, proceeed to installation.
echo "If profisee is installed, uninstall it first."
profiseepresent=$(helm list -n profisee -f profiseeplatform -o table --short)
if [ "$profiseepresent" = "profiseeplatform" ]; then
	helm -n profisee uninstall profiseeplatform;
	echo "Will sleep for 30 seconds to allow clean uninstall."
	sleep 30;
fi

echo "If we are using Key Vault and Profisee was uninstalled, then the profisee-license, profisee-sql-username, profisee-sql-password and profisee-tls-ingress secrets are missing. We need to find and restart the key-vault pod so that we can re-pull and re-mount the secrets."
#Find and delete the key-vault pod
if [ "$USEKEYVAULT" = "Yes" ]; then
	findkvpod=$(kubectl get pods -n profisee -o jsonpath='{.items[?(@.metadata.labels.app=="profisee-keyvault")].metadata.name}')
	if [ "$findkvpod" = "$findkvpod" ]; then
	echo $"Profisee Key Vault pod name is $findkvpod, deleting it."
	kubectl delete pod -n profisee $findkvpod --force --grace-period=0
	echo "Now let's install Profisee."
	helm install -n profisee profiseeplatform profisee/profisee-platform --values Settings.yaml
	fi
else
	echo "Now let's install Profisee."
	helm install -n profisee profiseeplatform profisee/profisee-platform --values Settings.yaml
fi
	
kubectl delete secret profisee-deploymentlog -n profisee --ignore-not-found
kubectl create secret generic profisee-deploymentlog -n profisee --from-file=$logfile

#Make sure it installed, if not return error
profiseeinstalledname=$(echo $(helm list --filter 'profisee+' -n profisee -o json)| jq '.[].name')
if [ -z "$profiseeinstalledname" ]; then
	echo "Profisee did not get installed. Exiting with error";
	exit 1
else
	echo "Installation of Profisee finished $(date +"%Y-%m-%d %T")";
fi;
#################################Install Profisee End #######################################

#Wait for pod to be ready (downloaded)
echo "Waiting for pod to be downloaded and be ready..$(date +"%Y-%m-%d %T")";
sleep 30;
kubectl wait --timeout=1800s --for=condition=ready pod/profisee-0 -n profisee

echo $"Profisee deploymented finished $(date +"%Y-%m-%d %T")";

result="{\"Result\":[\
{\"IP\":\"$nginxip\"},\
{\"WEBURL\":\"${EXTERNALDNSURL}/${WEBAPPNAME}\"},\
{\"FILEREPOUSERNAME\":\"$FILEREPOUSERNAME\"},\
{\"FILEREPOURL\":\"$FILEREPOURL\"},\
{\"AZUREAPPCLIENTID\":\"$CLIENTID\"},\
{\"AZUREAPPREPLYURL\":\"$azureAppReplyUrl\"},\
{\"SQLSERVER\":\"$SQLNAME\"},\
{\"SQLDATABASE\":\"$SQLDBNAME\"},\
{\"ACRREPONAME\":\"$ACRREPONAME\"},\
{\"ACRREPOLABEL\":\"$ACRREPOLABEL\"}\
]}"

echo $result

kubectl delete secret profisee-deploymentlog -n profisee --ignore-not-found
kubectl create secret generic profisee-deploymentlog -n profisee --from-file=$logfile

echo $result > $AZ_SCRIPTS_OUTPUT_PATH
