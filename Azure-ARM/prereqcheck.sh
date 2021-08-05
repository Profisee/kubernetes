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

echo $"RESOURCEGROUPNAME is $RESOURCEGROUPNAME"
echo $"SUBSCRIPTIONID is $SUBSCRIPTIONID"
echo $"DOMAINNAMERESOURCEGROUP is $DOMAINNAMERESOURCEGROUP"
echo $"UPDATEDNS is $UPDATEDNS"
echo $"UPDATEAAD is $UPDATEAAD"
echo $"USEKEYVAULT is $USEKEYVAULT"
echo $"KEYVAULT is $KEYVAULT"

IFS='/' read -r -a miparts <<< "$AZ_SCRIPTS_USER_ASSIGNED_IDENTITY" #splits the mi on slashes
mirg=${miparts[4]}
miname=${miparts[8]}

#remove white space
miname=$(echo $miname | xargs)

#get the id of the current user (MI)
echo "Running az identity show -g $mirg -n $miname --query principalId -o tsv"
currentIdentityId=$(az identity show -g $mirg -n $miname --query principalId -o tsv)

if [ -z "$currentIdentityId" ]; then
	err="Unable to query Managed Identity to get principal id.  Exiting with error."
	echo $err
	set_resultAndReturn;
fi

#Check to make sure you have effective contributor access to the resource group.  at RG or sub levl
#check subscription level

echo "Checking contributor level for subscription"
subscriptionContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='Contributor' && scope=='/subscriptions/$SUBSCRIPTIONID'].roleDefinitionName" --output tsv)
if [ -z "$subscriptionContributor" ]; then
	echo "Managed Identity is NOT contributor at subscription level, checking resource group"
	#not subscription level, check resource group level
	rgContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='Contributor' && scope=='/subscriptions/$SUBSCRIPTIONID/resourceGroups/$RESOURCEGROUPNAME'].roleDefinitionName" --output tsv)
	if [ -z "$rgContributor" ]; then
		err="Managed Identity is not Contributor to resource group.  Exiting with error."
		echo $err
		set_resultAndReturn;
	else
		echo "Managed Identity is Contributor to resource group."
	fi

	#If updating dns, check to make sure you have effective contributor access to the dns resource group
	if [ "$UPDATEDNS" = "Yes" ]; then
		echo "Checking contributor for DNS resource group"
		dnsrgContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='Contributor' && scope=='/subscriptions/$SUBSCRIPTIONID/resourceGroups/$DOMAINNAMERESOURCEGROUP'].roleDefinitionName" --output tsv)
		if [ -z "$dnsrgContributor" ]; then
			err="Managed Identity is not Contributor to DNS resource group.  Exiting with error."
			echo $err
			set_resultAndReturn;
		else
			echo "Managed Identity is Contributor to DNS resource group."
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
	echo "Managed Identity is Contributor at subscription level."
fi

#If using keyvault, check to make sure you have Managed Identity Contributor role AND User Access Administrator
if [ "$USEKEYVAULT" = "Yes" ]; then
	echo "In KeyVault checks"
	echo "Checking Managed Identity Contributor at subscription level."
	subscriptionMIContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='Managed Identity Contributor' && scope=='/subscriptions/$SUBSCRIPTIONID'].roleDefinitionName" --output tsv)
	if [ -z "$subscriptionMIContributor" ]; then
		err="Managed Identity is not Managed Identity Contributor at subscription level.  Exiting with error."
		echo $err
		set_resultAndReturn;
	else
		echo "Managed Identity is Managed Identity Contributor at subscription level."
	fi

	echo "Checking User Access Administrator at subscription level."
	subscriptionUAAContributor=$(az role assignment list --all --assignee $currentIdentityId --output json --include-inherited --query "[?roleDefinitionName=='User Access Administrator' && scope=='/subscriptions/$SUBSCRIPTIONID'].roleDefinitionName" --output tsv)
	if [ -z "$subscriptionUAAContributor" ]; then
		err="Managed Identity is not User Access Administrator at subscription level.  Exiting with error."
		echo $err
		set_resultAndReturn;
	else
		echo "Managed Identity is User Access Administrator at subscription level."
	fi
fi

#If updating AAD, make sure you have Application Administrator role
if [ "$UPDATEAAD" = "Yes" ]; then
	echo "Checking Application Administrator Role"
	appDevRoleId=$(az rest --method get --url https://graph.microsoft.com/v1.0/directoryRoles/ | jq -r '.value[] | select(.displayName | contains("Application Administrator")).id')
	minameinrole=$(az rest --method GET --uri "https://graph.microsoft.com/beta/directoryRoles/$appDevRoleId/members" | jq -r '.value[] | select(.displayName | contains("'"$miname"'")).displayName')
	if [ -z "$minameinrole" ]; then
		err="Managed Identity is not in Application Administrator role.  Exiting with error."
		echo $err
		set_resultAndReturn;
	else
		echo "Managed Identity is in Application Administrator role."
	fi
fi

success='true'


echo $"Profisee pre-req check finished $(date +"%Y-%m-%d %T")";

result="{\"Result\":[\
{\"SUCCESS\":\"$success\"}
]}"
echo $result > $AZ_SCRIPTS_OUTPUT_PATH


