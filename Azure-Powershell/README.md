# Deploy Profisee platform to AKS using powershell

The following is a step-by-step tutorial of deploying an Azure
Kubernetes Service container. On this container, the Profisee Platform
is installed and configured.

# Prerequisites:

1. License
	- Profisee license associated with the dns for the environment
	
	- Token for access to the profisee container
	
2. Software
	
	- Azure CLI - 2.5 or higher

	- Chocolatey

	- Kubernetes-Helm

3. Permissions
	
	- We’ll need an Azure AD account that has the following permissions:
	
		- Create resource groups 
		
		- Edit/create Azure Active directory app registrations (unless this is created manually)
		
		- Edit DNS Zones (unless you are using an external DNS registry somewhere other than Azure)
		
4. Certificates

	- Https certificate and its private key: This could be a wildcard certificate such as *.Company.com, or you could create an explicit certificate for this specific deployment, which will need to match the DNS entry we’ll be create. For example: profisee2020beta.company.com

# Setup:

## A – GitHub Repository

Clone the following GitHub repository to your local machine:

  - <https://github.com/Profisee/kubernetes/tree/master/Azure-Powershell>

## B - Certificates & Auth

1.  Set the TLS certificate value in Values.yaml

2.  Set the TLS key value in Values.yaml

3.  Set the image auth value which will be provided by Profisee

## C - Set variables in DeployProfiseePlatform.ps1

The following properties must be set:

	###Resource group###
	$createResourceGroup = $true #Set to false if you want to use an existing resource group (we recommend a new resource group ($true)). 
	$resourceGroupName = "resourcegroupname" #The resource group within which the new AKS cluster will be located. 
	$resourceGroupLocation = "eastus2" #Which Azure data center will this run in, ex: eastus2. Only necessary if creating a new resource group.

	###SQL###
	$createSqlServer = $true #Set this to true if you want to create a new SQL Server. False if you want to use an existing Azure SQL Server.
	$sqlServerResourceGroup = $resourceGroupName #(or specify the resource group of an existing Azure SQL Server)
	$sqlServerName = $resourceGroupName + "sql" #(or specify the Name of an existing Azure SQL Server)
	$sqlDatabaseName = "databasename" #(the database to create and/or use)
	$sqlUserName = "username" #Self-explanatory
	$sqlPassword = "password" #Self-explanatory

	###DNS###
	$createDNSRecord = $true #Set this to true if you are using a DNS Zone in Azure. False if you’re maintaining DNS somewhere else (we’ll have to update that DNS entry manually).
	$domainNameResourceGroup = "resourcegroupname" #This is the resource group of the DNS zone where the DNS record should be created/updated. You can find this in the Azure Portal.
	$domainName = "yourdomain.com" #Typically the root domain of your company/organization. For example, Profisee’s is Profisee.com
	$hostName = "hostname" #Typically equivalent to the environment or machine name. 

	##File Repository###
	$createFileRepository = $true #Set this to true if you want to create a new storage account. False if you want to use an existing storage account.
	$storageAccountName = $resourceGroupName + "files" #(or specify an existing one if you’re using an existing storage account)
	$storageShareName = "files" #(or specify an existing one if you’re using an existing storage account)

	###Azure AD App Registration###
	$createAppInAzureAD = $true #Set this to true if you haven’t manually registered the application and redirect URI.
	$azureClientName = "clientname" #Required if createAppInAzureAd = true. Unused if false.
	$azureClientId = "" #Required if createAppInAzureAd = false. Unused if true.
	$azureClientSecret = "" #Optional if createAppInAzureAd = true. Unused if false.

	###Profisee platform###
	$adminAccountForPlatform = "emailaddress@domain.com" #This should be account of the first super user who will be registered with Profisee, who will be able to logon and add other users.

	###AKS Settings###
	$clusterVmSizeForLinux = "Standard_D4as_v5" #This should be fine, but we could change it if we determine we should. Used primarily for networking/load balancing controllers (Linux).
	$clusterVmSizeForWindows = "Standard_D8as_v5" #We’ll want to ensure the correct size 
	$kubernetesVersion = "1.24.10"

## D - Set the Azure AD redirect URI if you did not have the deploy update it for you.

1.  Navigate to the Azure Portal

2.  Go to Azure Active Directory -\> App Registrations -\> New
    Registration

3.  Configure with the following properties:
    
      - Name can be whatever you'd like
    
      - Single tenant
    
      - URI config:
        
          - Web
        
          - URI:
            https://\<hostName\>.\<domainName\>/Profisee/auth/signin-microsoft  

4.  Click Register

5.  Navigate to the new registration -\> Authentication

6.  Under "Implicit grant" check the box for "ID tokens"

7.  Click Save

8.  Navigate back to the overview page for the new app registration.

9.  Copy the value for Application (client) ID; we will need this in
    Section C.

# Run:

1.  Run the powershell script: DeployProfiseePlatform.ps1

2.  Wait approx. 20 mins

# Verify:

1.  The initial deploy will have to download the container which takes about 10 minutes.  Verify its finished downloading the container:

		kubectl describe pod profisee-0 #check status and wait for "Pulling" to finish

1.  Container can be accessed with the following command:
    
        kubectl exec -it profisee-0 powershell

2.  System logs can be accessed with the following command:
    
        Get-Content C:\\Profisee\\Configuration\\LogFiles\\SystemLog.log
