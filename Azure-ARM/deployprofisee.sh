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
# az extension add --name aks-preview
# az extension update --name aks-preview
# az feature register --namespace "Microsoft.ContainerService" --name "EnableWorkloadIdentityPreview"
# az feature show --namespace "Microsoft.ContainerService" --name "EnableWorkloadIdentityPreview"
# az provider register --namespace Microsoft.ContainerService

#Install dotnet core.
echo $"Installation of dotnet core started.";
curl -fsSL -o dotnet-install.sh https://dot.net/v1/dotnet-install.sh
#Set permisssions for installation script.
chmod 755 ./dotnet-install.sh
#Install dotnet.
./dotnet-install.sh -c LTS
echo $"Installation of dotnet core finished.";

#Downloadind and extracting Proisee license reader.
echo $"Download of Profisee license reader started.";
curl -fsSL -o LicenseReader "$REPOURL/Utilities/LicenseReader/LicenseReader"
#curl -fsSL -o LicenseReader.tar.002 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.002"
#curl -fsSL -o LicenseReader.tar.003 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.003"
#curl -fsSL -o LicenseReader.tar.004 "$REPOURL/Utilities/LicenseReader/LicenseReader.tar.004"
#cat LicenseReader.tar.* | tar xf -
#rm LicenseReader.tar.001
#rm LicenseReader.tar.002
#rm LicenseReader.tar.003
#rm LicenseReader.tar.004
echo $"Download of Profisee license reader finished.";

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

version="$(curl -fsSL https://dl.k8s.io/release/stable.txt || true)"
echo $"kubectl version is $version"

if [[ -z "$version" ]]; then
  version="v1.35.0"
  echo "Failed to fetch latest kubectl version. Falling back to $version"
else
  echo "Latest kubectl version is $version"
fi

curl -fsSLo kubectl "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

echo "Installation of kubectl finished."
kubectl version --client --output=yaml

sleep 60

#Create profisee namespace in AKS cluster.
echo $"Creation of profisee namespace in cluster started. If present, we skip creation and use it.";
sleep 30
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
		kvcsipresentinkubesystem=$(helm list -n kube-system -f csi-secrets-store-provider-azure -o table --short)
        if [ "$kvcsipresentinkubesystem" = "csi-secrets-store-provider-azure" ]; then
	        helm uninstall -n kube-system csi-secrets-store-provider-azure;
	        echo $"Will sleep for 30 seconds to allow clean uninstall of Key Vault CSI driver."
	        sleep 30;
        fi

	#We are not but if this is to run on a windows node, then you use this --set windows.enabled=true --set secrets-store-csi-driver.windows.enabled=true
	#Recommendation is to have CSI installed in kube-system as per https://azure.github.io/secrets-store-csi-driver-provider-azure/docs/getting-started/installation/
	helm install -n kube-system csi-secrets-store-provider-azure csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --set secrets-store-csi-driver.syncSecret.enabled=true
	echo $"Installation of Key Vault Container Storage Interface (CSI) driver finished."

	#Install Azure Workload Identity driver.
	echo $"Installation of Key Vault Azure Active Directory Workload Identity driver started."
    #az aks update -g $RESOURCEGROUPNAME -n $CLUSTERNAME --enable-oidc-issuer --enable-workload-identity
	OIDC_ISSUER="$(az aks show -n $CLUSTERNAME -g $RESOURCEGROUPNAME --query "oidcIssuerProfile.issuerUrl" -o tsv)"
	echo $"Installation of Key Vault Azure Active Directory Workload Identity driver finished."

	#Uninstall AAD pod identity from AKS.
	echo $"Uninstallation of Key Vault Azure Active Directory Pod Identity driver started. If present, we uninstall it."
	#If AAD Pod Identity is present, uninstall it.
        aadpodpresent=$(helm list -n profisee -f pod-identity -o table --short)
        if [ "$aadpodpresent" = "pod-identity" ]; then
	        helm uninstall -n profisee pod-identity;
	        echo $"Will sleep for 30 seconds to allow clean uninstall of AAD Pod Identity."
	        sleep 30;
        fi
	#AAD Pod identity is no longed required, replaced by Workload Identity.
	#helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
	#helm install -n profisee pod-identity aad-pod-identity/aad-pod-identity
	#echo $"Installation of Key Vault Azure Active Directory Pod Identity driver finished."

	#Assign AAD roles to the AKS AgentPool Managed Identity.
	echo $"AKS Managed Identity configuration for Key Vault access started."

	echo $"AKS AgentPool Managed Identity configuration for Key Vault access step 1 started."
	echo "Running az role assignment create --role "Managed Identity Operator" --assignee-object-id $KUBERNETESOBJECTID --assignee-principal-type ServicePrincipal --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$RESOURCEGROUPNAME"
	az role assignment create --role "Managed Identity Operator" --assignee-object-id $KUBERNETESOBJECTID --assignee-principal-type ServicePrincipal --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$RESOURCEGROUPNAME
	echo "Running az role assignment create --role "Managed Identity Operator" --assignee-object-id $KUBERNETESOBJECTID --assignee-principal-type ServicePrincipal --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME"
	az role assignment create --role "Managed Identity Operator" --assignee-object-id $KUBERNETESOBJECTID --assignee-principal-type ServicePrincipal --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME
	echo "Running az role assignment create --role "Virtual Machine Contributor" --assignee-object-id $KUBERNETESOBJECTID --assignee-principal-type ServicePrincipal --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME"
	az role assignment create --role "Virtual Machine Contributor" --assignee-object-id $KUBERNETESOBJECTID --assignee-principal-type ServicePrincipal --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$AKSINFRARESOURCEGROUPNAME
	echo $"AKS AgentPool Managed Identity configuration for Key Vault access step 1 finished."

	#Create Azure AD Managed Identity specifically for Key Vault, get its ClientiId and PrincipalId so we can assign to it the Reader role in steps 3a, 3b and 3c to.
	echo $"Key Vault Specific Managed Identity configuration for Key Vault access step 2 started."
	identityName="AKSKeyVaultUser"
	akskvidentityClientId=$(az identity create -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'clientId' -o tsv);

	#Create Federated Credential and assign it to the Profisee Service Account
	az identity federated-credential create --name ProfiseefederatedId --identity-name $identityName  --resource-group $AKSINFRARESOURCEGROUPNAME --issuer $OIDC_ISSUER --subject system:serviceaccount:profisee:profiseeserviceaccount --audience api://AzureADTokenExchange
	akskvidentityClientResourceId=$(az identity show -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'id' -o tsv)
	principalId=$(az identity show -g $AKSINFRARESOURCEGROUPNAME -n $identityName --query 'principalId' -o tsv)
	echo $"Key Vault Specific Managed Identity configuration for Key Vault access step 2 finished."

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
	echo $"keyVaultResourceGroup is $keyVaultResourceGroup"
	echo $"akskvidentityClientId is $akskvidentityClientId"
	echo $"principalId is $principalId"

    #Check if Key Vault is RBAC or policy based.
    echo $"Checking if Key Vauls is RBAC based or policy based"
	rbacEnabled=$(az keyvault show --name $keyVaultName --subscription $keyVaultSubscriptionId --resource-group $keyVaultResourceGroup --query "properties.enableRbacAuthorization")
	echo $"rbac enabled is $rbacEnabled"
    #If Key Vault is RBAC based, assign Key Vault Secrets User role to the Key Vault Specific Managed Identity, otherwise assign Get policies for Keys, Secrets and Certificates.
    if [ "$rbacEnabled" = true ]; then
		echo $"Setting Key Vault Secrets User RBAC role to the Key Vault Specific Managed Identity."
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
auth="$(echo -n "$ACRUSER:$ACRUSERPASSWORD" | base64 -w0)"
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
	CLIENTID=$(az ad app create --display-name $azureClientName --web-redirect-uris $azureAppReplyUrl --enable-id-token-issuance --query 'appId' -o tsv);
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
	    az ad app permission grant --id $CLIENTID --api 00000003-0000-0000-c000-000000000000 --scope User.Read
	    echo "Update of the application registration's permissions, step 2 finished."
	    echo "Update of Azure Active Directory finished.";
	fi
	#If Azure Application Registration "groups" token is present, skip adding it.
	echo $"Let's check to see if the "groups" token is present, skip if present."
    appregtokengroupsclaimpresent=$(az ad app list --app-id $CLIENTID --query "[].optionalClaims[].idToken[].name" -o tsv)
    if [ "$appregtokengroupsclaimpresent" = "groups" ]; then
	    echo $"Token is configured with groups token claim, no need to add it."
	else
	    echo "Update of the application registration's token configuration started."
	    #Add a groups claim token for idTokens
	    az ad app update --id $CLIENTID --set groupMembershipClaims=ApplicationGroup --optional-claims '{"idToken":[{"additionalProperties":[],"essential":false,"name":"groups","source":null}],"accessToken":[{"additionalProperties":[],"essential":false,"name":"groups","source":null}],"saml2Token":[{"additionalProperties":[],"essential":false,"name":"groups","source":null}]}'
		appregidtokengroupsclaimpresent=$(az ad app list --app-id $CLIENTID --query "[].optionalClaims[].idToken[].name" -o tsv)
		appregaccesstokengroupsclaimpresent=$(az ad app list --app-id $CLIENTID --query "[].optionalClaims[].accessToken[].name" -o tsv)
		appregsaml2tokengroupsclaimpresent=$(az ad app list --app-id $CLIENTID --query "[].optionalClaims[].saml2Token[].name" -o tsv)
		echo $"idToken claim is now '$appregidtokengroupsclaimpresent'"
		echo $"accessToken claim is now '$appregaccesstokengroupsclaimpresent'"
		echo $"saml2Token claim is now '$appregsaml2tokengroupsclaimpresent'"
	    echo "Update of the application registration's token configuration finished."
	fi
	#Create application Registration secret to be used for Authentication.
	echo $"Let's check to see if an application registration secret has been created for Profisee, we'll recreate it if it is present as it can only be acquired during creation."
    appregsecretpresent=$(az ad app list --app-id $CLIENTID --query "[].passwordCredentials[?displayName=='Profisee env in cluster $CLUSTERNAME'].displayName | [0]" -o tsv)
	if [ "$appregsecretpresent" = "Profisee env in cluster $CLUSTERNAME" ]; then
	    echo $"Application registration secret for 'Profisee in cluster $CLUSTERNAME' is already present, but need to recreate it. Acquiring secret ID so it can be deleted."
		appregsecretid=$(az ad app list --app-id $CLIENTID --query "[].passwordCredentials[?displayName=='Profisee env in cluster $CLUSTERNAME'].keyId | [0]" -o tsv)
		echo $"Application registration secret ID is $appregsecretid, deleting it."
		az ad app credential delete --id $CLIENTID --key-id $appregsecretid
		echo $"Application registration secret ID $appregsecretid has been deleted."
		echo "Will sleep for 10 seconds to avoid request concurrency errors."
		sleep 10
		echo "Creating new application registration secret now."
		CLIENTSECRET=$(az ad app credential reset --id $CLIENTID --append --display-name "Profisee env in cluster $CLUSTERNAME" --years 2 --query "password" -o tsv)
	else
	    echo "Secret for cluster $CLUSTERNAME does not exist, creating it."
	    echo "Creating new application registration secret now."
		CLIENTSECRET=$(az ad app credential reset --id $CLIENTID --append --display-name "Profisee env in cluster $CLUSTERNAME" --years 2 --query "password" -o tsv)
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

echo $"Correction of TLS variables finished.";

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

#Acquire the collection id from the collection name
if [ "$USEPURVIEW" = "Yes" ]; then
	echo "Obtain collection id from provided collection friendly name started.";
	echo "Grab a token."
	purviewtoken=$(curl --location --no-progress-meter --request GET "https://login.microsoftonline.com/$TENANTID/oauth2/token" --header 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "client_id=$PURVIEWCLIENTID" --data-urlencode "client_secret=$PURVIEWCLIENTSECRET" --data-urlencode 'grant_type=client_credentials' --data-urlencode 'resource=https://purview.azure.net'  | jq --raw-output '.access_token');
	echo "Token acquired."
	echo "Find collection Id.";
	echo $"Stripping /catalog from $PURVIEWURL."
	PURVIEWACCOUNTFQDN=${PURVIEWURL::-8}
	echo $"Purview account name is $PURVIEWACCOUNTFQDN. Using it."
	COLLECTIONTRUEID=$(curl --location --no-progress-meter --request GET "$PURVIEWACCOUNTFQDN/account/collections?api-version=2019-11-01-preview" --header "Authorization: Bearer $purviewtoken" | jq --raw-output '.value | .[] | select(.friendlyName=="'$PURVIEWCOLLECTIONID'") | .name')
	echo $"Collection id is $COLLECTIONTRUEID, using that.";
	echo "Obtain collection id from provided collection friendly name completed.";
fi

echo "The variables will now be set in the Settings.yaml file"
#Setting storage related variables
FILEREPOUSERNAME="Azure\\\\\\\\${STORAGEACCOUNTNAME}"
FILEREPOURL="\\\\\\\\\\\\\\\\${STORAGEACCOUNTNAME}.file.core.windows.net\\\\\\\\${STORAGEACCOUNTFILESHARENAME}"

#PROFISEEVERSION looks like this profiseeplatform:2023R1.0
#The repository name is profiseeplatform, it is everything to the left of the colon sign :
#The label is everything to the right of the :

IFS=':' read -r -a repostring <<< "$PROFISEEVERSION"

#lowercase is the ,,
ACRREPONAME="${repostring[0],,}";
ACRREPOLABEL="${repostring[1],,}"

#Installation of Azure File CSI Driver
WINDOWS_NODE_VERSION="$(az aks show -n $CLUSTERNAME -g $RESOURCEGROUPNAME --query "agentPoolProfiles[1].osSku" -o tsv)"
if [ "$WINDOWS_NODE_VERSION" = "Windows2019" ]; then
	#Disable built-in AKS file driver, will install further down.
	echo $"Disabling AKS Built-in CSI Driver to install Azure File CSI."
	az aks update -n $CLUSTERNAME -g $RESOURCEGROUPNAME --disable-file-driver --yes
	echo $"Installation of Azure File CSI Driver started. If present, we uninstall it first.";
	azfilecsipresent=$(helm list -n kube-system -f azurefile-csi-driver -o table --short)
	if [ "$azfilecsipresent" = "azurefile-csi-driver" ]; then
		helm -n kube-system uninstall azurefile-csi-driver;
		echo "Will sleep for 30 seconds to allow clean uninstall."
		sleep 30;
	fi
	echo $"Adding Azure File CSI Driver repo."
	helm repo add azurefile-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/azurefile-csi-driver/master/charts
	helm repo update azurefile-csi-driver
	#Controller Replicas MUST be 2 in Prod, okay to be 1 in Dev (i.e. do NOT add --set controller.replica=1 in Prod). This is dependent on number of available Linux nodes in the nodepool. In Prod, it is minimum of 2, Dev is 1.
	helm install azurefile-csi-driver azurefile-csi-driver/azurefile-csi-driver --namespace kube-system
	echo $"Azure File CSI Driver installation finished."
fi

#Add AzureAD Claims and Pod Count
OIDCNAME="Azure Active Directory"
OIDCCMUserName="http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
OIDCCMUserID="http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"
OIDCCMFirstName="http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname"
OIDCCMLastName="http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"
OIDCCMEmailAddress="http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"

PodCount=1

sed -i -e 's~$OIDCNAME~'"$OIDCNAME"'~g' Settings.yaml
sed -i -e 's~$OIDCCMUserName~'"$OIDCCMUserName"'~g' Settings.yaml
sed -i -e 's~$OIDCCMUserID~'"$OIDCCMUserID"'~g' Settings.yaml
sed -i -e 's~$OIDCCMFirstName~'"$OIDCCMFirstName"'~g' Settings.yaml
sed -i -e 's~$OIDCCMLastName~'"$OIDCCMLastName"'~g' Settings.yaml
sed -i -e 's~$OIDCCMEmailAddress~'"$OIDCCMEmailAddress"'~g' Settings.yaml

sed -i -e 's/$PodCount/'"$PodCount"'/g' Settings.yaml


#pre,post init script and oidcfiledata
preInitScriptData="Cg=="
postInitScriptData="Cg=="
OIDCFileData="{\n    }"
echo $OIDCFileData
sed -i -e 's/$preInitScriptData/'"$preInitScriptData"'/g' Settings.yaml
sed -i -e 's/$postInitScriptData/'"$postInitScriptData"'/g' Settings.yaml
sed -i -e 's/$OIDCFileData/'"$OIDCFileData"'/g' Settings.yaml


#Get the vCPU and RAM so we can change the stateful set CPU and RAM limits on the fly.
echo "Let's see how many vCPUs and how much RAM we can allocate to Profisee's pod on the Windows node size you've selected."
findwinnodename=$(kubectl get nodes -l kubernetes.io/os=windows -o 'jsonpath={.items[0].metadata.name}')
findallocatablecpu=$(kubectl get nodes $findwinnodename -o 'jsonpath={.status.allocatable.cpu}')
findallocatablememory=$(kubectl get nodes $findwinnodename -o 'jsonpath={.status.allocatable.memory}')
vcpubarevalue=${findallocatablecpu::-1}
safecpuvalue=$(($vcpubarevalue-800))
safecpuvalueinmilicores="${safecpuvalue}m"
echo $"The safe vCPU value to assign to Profisee pod is $safecpuvalueinmilicores."
#Math around safe RAM values
vrambarevalue=${findallocatablememory::-2}
saferamvalue=$(($vrambarevalue-2253125))
saferamvalueinkibibytes="${saferamvalue}Ki"
echo $"The safe RAM value to assign to Profisee pod is $saferamvalueinkibibytes."
# helm -n profisee install profiseeplatform profisee/profisee-platform --values Settings.yaml
# #Patch stateful set for safe vCPU and RAM values
# kubectl patch statefulsets -n profisee profisee --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value":'"$safecpuvalueinmilicores"'}]'
# echo $"Profisee's stateful set has been patched to use $safecpuvalueinmilicores for CPU."
# kubectl patch statefulsets -n profisee profisee --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value":'"$saferamvalueinkibibytes"'}]'
# echo $"Profisee's stateful set has been patched to use $saferamvalueinkibibytes for RAM."
curl -fsSL -o coredns-custom.yaml "$REPOURL/Azure-ARM/coredns-custom.yaml";
sed -i -e 's/$EXTERNALDNSNAME/'"$EXTERNALDNSNAME"'/g' coredns-custom.yaml

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
sed -i -e 's/$OIDCCLIENTSECRET/'"$CLIENTSECRET"'/g' Settings.yaml
sed -i -e 's/$ADMINACCOUNTNAME/'"$ADMINACCOUNTNAME"'/g' Settings.yaml
sed -i -e 's~$EXTERNALDNSURL~'"$EXTERNALDNSURL"'~g' Settings.yaml
sed -i -e 's/$EXTERNALDNSNAME/'"$EXTERNALDNSNAME"'/g' Settings.yaml
sed -i -e 's~$LICENSEDATA~'"$LICENSEDATA"'~g' Settings.yaml
sed -i -e 's/$ACRREPONAME/'"$ACRREPONAME"'/g' Settings.yaml
sed -i -e 's/$ACRREPOLABEL/'"$ACRREPOLABEL"'/g' Settings.yaml
sed -i -e 's~$PURVIEWURL~'"$PURVIEWURL"'~g' Settings.yaml
sed -i -e 's/$PURVIEWTENANTID/'"$TENANTID"'/g' Settings.yaml
sed -i -e 's/$PURVIEWCOLLECTIONID/'"$COLLECTIONTRUEID"'/g' Settings.yaml
sed -i -e 's/$PURVIEWCLIENTID/'"$PURVIEWCLIENTID"'/g' Settings.yaml
sed -i -e 's/$PURVIEWCLIENTSECRET/'"$PURVIEWCLIENTSECRET"'/g' Settings.yaml
sed -i -e 's/$WEBAPPNAME/'"$WEBAPPNAME"'/g' Settings.yaml
sed -i -e 's/$CPULIMITSVALUE/'"$safecpuvalueinmilicores"'/g' Settings.yaml
sed -i -e 's/$MEMORYLIMITSVALUE/'"$saferamvalueinkibibytes"'/g' Settings.yaml
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
	helm install cert-manager jetstack/cert-manager -n profisee --version v1.17.0 --set crds.enabled=true --set nodeSelector."kubernetes\.io/os"=linux --set webhook.nodeSelector."kubernetes\.io/os"=linux --set cainjector.nodeSelector."kubernetes\.io/os"=linux --set startupapicheck.nodeSelector."kubernetes\.io/os"=linux
	# Wait for the cert manager to be ready
	echo $"Let's Encrypt is waiting for certificate manager to be ready, sleeping for 30 seconds.";
	sleep 30;
	sed -i -e 's/$USELETSENCRYPT/'true'/g' Settings.yaml
	sed -i -e 's/$INFRAADMINACCOUNT/'"$INFRAADMINACCOUNT"'/g' Settings.yaml
	echo "Let's Encrypt installation finshed";
	#################################Lets Encrypt End #######################################
else
	sed -i -e 's/$USELETSENCRYPT/'false'/g' Settings.yaml
fi

#Adding Settings.yaml as a secret generated only from the initial deployment of Profisee. Future updates, such as license changes via the profisee-license secret, or SQL credentials updates via the profisee-sql-password secret, will NOT be reflected in this secret. Proceed with caution!
kubectl delete secret profisee-settings -n profisee --ignore-not-found
kubectl create secret generic profisee-settings -n profisee --from-file=Settings.yaml

#Replacing Coredns with custom coredns config map
kubectl replace -f ./coredns-custom.yaml

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
	echo "Profisee is not installed, proceeding to install it."
	helm -n profisee install profiseeplatform profisee/profisee-platform --values Settings.yaml

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

#Change Authentication context: disable local accounts, Enabled Azure AD with Azure RBAC and assign the Azure Kubernetes Service RBAC Cluster Admin role to the Profisee Super Admin account.
echo $"AuthenticationType is $AUTHENTICATIONTYPE";
echo $"Resourcegroup is $RESOURCEGROUPNAME";
echo $"WindowsNodeVersion is $WINDOWSNODEVERSION";
echo $"clustername is $CLUSTERNAME";
if [ "$AUTHENTICATIONTYPE" = "AzureRBAC" ]; then
	az aks update -g $RESOURCEGROUPNAME -n $CLUSTERNAME --enable-aad --enable-azure-rbac --disable-local-accounts
	ObjectId="$(az ad user show --id $ADMINACCOUNTNAME --query id -o tsv)"
	echo $"ObjectId of ADMIN is $ObjectId";
	az role assignment create --role "Azure Kubernetes Service RBAC Cluster Admin" --assignee-object-id $ObjectId --assignee-principal-type User --scope /subscriptions/$SUBSCRIPTIONID/resourcegroups/$RESOURCEGROUPNAME
fi;

echo $result > $AZ_SCRIPTS_OUTPUT_PATH
