#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
logfile=prereqchecklog_$(date +%Y-%m-%d_%H-%M-%S).out
exec 1>$logfile 2>&1

echo $"Profisee pre-req check started $(date +"%Y-%m-%d %T")";

printenv;

if [ -z "$RESOURCEGROUPNAME" ]; then
	RESOURCEGROUPNAME=$ResourceGroupName
fi

if [ -z "$SUBSCRIPTIONID" ]; then
	SUBSCRIPTIONID=$SubscriptionId
fi

#az login --identity

success='false'

function set_resultAndReturn () {
	result="{\"Result\":[\
	{\"SUCCESS\":\"$success\"},
	{\"ERROR\":\"$err\"}\
	]}"
	echo $result > $AZ_SCRIPTS_OUTPUT_PATH
	exit 1
}
echo $"DNSDOMAINNAME is $DNSDOMAINNAME"
echo $"RESOURCEGROUPNAME is $RESOURCEGROUPNAME"
echo $"SUBSCRIPTIONID is $SUBSCRIPTIONID"
echo $"DOMAINNAMERESOURCEGROUP is $DOMAINNAMERESOURCEGROUP"
echo $"UPDATEDNS is $UPDATEDNS"
echo $"UPDATEAAD is $UPDATEAAD"
echo $"USEKEYVAULT is $USEKEYVAULT"
echo $"KEYVAULT is $KEYVAULT"
echo $"USEPURVIEW is $USEPURVIEW"
echo $"PURVIEWURL is $PURVIEWURL"
echo $"PURVIEWCLIENTID is $PURVIEWCLIENTID"

IFS='/' read -r -a miparts <<< "$AZ_SCRIPTS_USER_ASSIGNED_IDENTITY" #splits the mi on slashes
mirg=${miparts[4]}
miname=${miparts[8]}

#Remove white space
miname=$(echo $miname | xargs)

#Get the ID of the current user (MI)
echo "Running az identity show -g $mirg -n $miname --query principalId -o tsv"
currentIdentityId=$(az identity show -g $mirg -n $miname --query principalId -o tsv)

if [ -z "$currentIdentityId" ]; then
	err="Unable to query the Deployment Managed Identity to get principal id. Exiting with error. IF the Deployment Managed Identity has just been created, this issue is most likely intermittent. Please retry your deployment."
	echo $err
	set_resultAndReturn;
fi

#Check to make sure you have effective Contributor access at either Resource group or Subscription level.
#Checking Subscription level first.

echo "Is the Deployment Managed Identity assigned the Contributor Role at the Subscription or at the Resource Group level?"
subscriptionContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='Contributor' && scope=='/subscriptions/$SUBSCRIPTIONID'].roleDefinitionName" --output tsv)
if [ -z "$subscriptionContributor" ]; then
	echo "Role is NOT assigned at Subscription level, checking Resource Group level assignment now. Please bear in mind that if you plan to have the Deployment Managed Identity create the Resource Group for you, then you will need to grant it Contributor role at Subscription level."
	#Deployment MAnaged Identity is not granted Contributor at Subscription level, checking Resource Group level.
	rgContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='Contributor' && scope=='/subscriptions/$SUBSCRIPTIONID/resourceGroups/$RESOURCEGROUPNAME'].roleDefinitionName" --output tsv)
	if [ -z "$rgContributor" ]; then
		err="Role is NOT assigned at either Subscription or Resource Group level. Exiting with error. Please assign the Contributor role to the Deployment Managed Identity at either Subscription or Resource Group level. Please visit https://support.profisee.com/wikis/2022_r1_support/planning_your_managed_identity_configuration for more information."
		echo $err
		set_resultAndReturn;
	else
		echo "Role is assigned at Resource level. Continuing checks."
	fi

	#If updating DNS, check to make sure you have effective contributor access to the DNS zone itself.
	if [ "$UPDATEDNS" = "Yes" ]; then
		echo "Is the Deployment Managed Identity assigned the DNS Zone Contributor role to the DNS zone itself?"
		dnsznContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='DNS Zone Contributor' && scope=='/subscriptions/$SUBSCRIPTIONID/resourceGroups/$DOMAINNAMERESOURCEGROUP/providers/Microsoft.Network/dnszones/$DNSDOMAINNAME'].roleDefinitionName" --output tsv)
		if [ -z "$dnsznContributor" ]; then
			err="Role is NOT assigned. Exiting with error. Please assign the DNS Zone Contributor role to the Deployment Managed Identity for the DNS zone you want updated. Please visit https://support.profisee.com/wikis/2022_r1_support/planning_your_managed_identity_configuration for more information."
			echo $err
			set_resultAndReturn;
		else
			echo "Role is assigned. Continuing checks."
		fi
	fi

	# #If using keyvault, check to make sure you have effective contributor access to the keyvault
	# if [ "$USEKEYVAULT" = "Yes" ]; then
	# 	echo "Checking contributor for keyvault"
	# 	KEYVAULT=$(echo $KEYVAULT | xargs)
	# 	kvContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='Contributor' && scope=='$KEYVAULT'].roleDefinitionName" --output tsv)
	# 	if [ -z "$kvContributor" ]; then
	# 		err="Managed Identity is not Contributor to KeyVault.  Exiting with error."
	# 		echo $err
	# 		set_resultAndReturn;
	# 	else
	# 		echo "Managed Identity is Contributor to KeyVault."
	# 	fi
	# fi

else
	echo "Role is assigned at Subsciption level. Continuing checks."
fi

# If using Purview, check for the following: 
# 1. Has the Purview Application Registration been added to the Data Curators role in the Purview account. If not, exit with error.
# 2. Does the Purview Application Registartion have the proper permissions. If not, output warnings and continue.
if [ "$USEPURVIEW" = "Yes" ]; then
	purviewClientPermissions=$(az ad app permission list --id $PURVIEWCLIENTID --output tsv --query [].resourceAccess[].id)
	
	#Check if User.Read permission has been granted to the Purview specific Azure Application Registration.
	if [[ $purviewClientPermissions != *"e1fe6dd8-ba31-4d61-89e7-88639da4683d"* ]]; then
		echo "The Purview Azure AD application registration is missing the Microsoft Graph API User.Read delegated permission. Some governance features may not function until this permission is granted. This permission might require an Azure AD Global Admin consent. Please visit https://support.profisee.com/wikis/2022_r1_support/prerequisites_for_integrating_with_purview for more information. "
	fi

	#Check if User.Read.All permission has been granted to the Purview specific Azure Application Registration.
	if [[ $purviewClientPermissions != *"df021288-bdef-4463-88db-98f22de89214"* ]]; then
		echo "The Purview Azure AD application registration is missing the Microsoft Graph API User.Read.All application permission. Some governance features will not function until this permission is granted. This permission requires an Azure AD Global Admin consent. Please visit https://support.profisee.com/wikis/2022_r1_support/prerequisites_for_integrating_with_purview for more information."
	fi

	#Check if Group.Read.All permission has been granted to the Purview specific Azure Application Registration.
	if [[ $purviewClientPermissions != *"5b567255-7703-4780-807c-7be8301ae99b"* ]]; then
		echo "The Purview Azure AD application registration is missing the Microsoft Graph API Group.Read.All application permission. Some governance features will not function until this permission is granted. This permission requires an Azure AD Global Admin consent. Please visit https://support.profisee.com/wikis/2022_r1_support/prerequisites_for_integrating_with_purview for more information."
	fi

	#Check if GroupMember.Read.All permission has been granted to the Purview specific Azure Application Registration.
	if [[ $purviewClientPermissions != *"98830695-27a2-44f7-8c18-0c3ebc9698f6"* ]]; then
		echo "The Purview Azure AD application registration is missing the Microsoft Graph API GroupMember.Read.All application permission. Some governance features will not function until this permission is granted. This permission requires an Azure AD Global Admin consent. Please visit https://support.profisee.com/wikis/2022_r1_support/prerequisites_for_integrating_with_purview for more information."
	fi
fi 

#If using Key Vault, checks to make sure that the Deployment Managed Identity has been assigned the Managed Identity Contributor role AND User Access Administrator as Subscription level.
if [ "$USEKEYVAULT" = "Yes" ]; then
	echo "Is the Deployment Managed Identity assigned the Managed Identity Contributor role at the Subscription level?"
	subscriptionMIContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='Managed Identity Contributor' && scope=='/subscriptions/$SUBSCRIPTIONID'].roleDefinitionName" --output tsv)
	if [ -z "$subscriptionMIContributor" ]; then
		err="Role is NOT assigned. Exiting with error. If using Key Vault, this role is required so that the Deployment Managed Identity can create the Managed Identity that will be used to communicated with Key Vault."
		echo $err
		set_resultAndReturn;
	else
		echo "Role is assigned. Continuing checks."
	fi

	echo "Is the Deployment Managed Identity assigned the User Access Administrator role at Subscription level?"
	subscriptionUAAContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='User Access Administrator' && scope=='/subscriptions/$SUBSCRIPTIONID'].roleDefinitionName" --output tsv)
	if [ -z "$subscriptionUAAContributor" ]; then
		err="The Deployment Managed Identity is NOT assigned the User Access Administrator at subscription level. Exiting with error. If using Key Vault, this role is required so that the Deployment Managed Identity can assign the Key Vault Secrets User role, if using RBAC KV, OR the Get policies, if using policy based KV, to the Key Vault Specific Managed Identity."
		echo $err
		set_resultAndReturn;
	else
		echo "Role is assigned. Continuing checks."
	fi
fi

#If Deployment Managed Identity will be creating the Azure AD application registration, make sure that the Application Administrator role is assigned to it.
if [ "$UPDATEAAD" = "Yes" ]; then
	echo "Is the Deployment Managed Identity assigned the Application Administrator Role in Azure Active Directory?"
	appDevRoleId=$(az rest --method get --url https://graph.microsoft.com/v1.0/directoryRoles/ | jq -r '.value[] | select(.displayName | contains("Application Administrator")).id')
	minameinrole=$(az rest --method GET --uri "https://graph.microsoft.com/beta/directoryRoles/$appDevRoleId/members" | jq -r '.value[] | select(.displayName | contains("'"$miname"'")).displayName')
	if [ -z "$minameinrole" ]; then
		err="The Deployment Managed Identity is NOT assigned the Application Administrator role in Azure Active Directory. Exiting with error. This role is required so that the Deployment Managed Identity can create the Azure AD Application registration. For more information please visit https://support.profisee.com/wikis/2022_r1_support/planning_your_managed_identity_configuration."
		echo $err
		set_resultAndReturn;
	else
		echo "Role is assigned. All checks completed."
	fi
fi

success='true'

echo $"Profisee pre-req check finished $(date +"%Y-%m-%d %T")";

result="{\"Result\":[\
{\"SUCCESS\":\"$success\"}
]}"
echo $result > $AZ_SCRIPTS_OUTPUT_PATH