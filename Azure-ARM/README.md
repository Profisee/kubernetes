# Deploy Profisee platform on to AKS using ARM template

This ARM template deploys Profisee platform into a new Azure Kubernetes service cluster.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FProfisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeploy.json)

## Prerequisites

1.  Managed Identity
    - A user assigned managed identity configured ahead of time.  The managed identity must have Contributor role for the resource group, and the DNS zone resource group if updating DNS.  This can be done by assigning the contributor role to each individual resource group, or assigning the subscription level resource group.  If creating an Azure Active Directory application registration, the managed identity must have the Application Developer role assigned to it.  https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-manage-ua-identity-portal
2.  License
    - Profisee license associated with the dns for the environment
    - Token for access to the profisee container
3.  Https certificate including the private key

## Deployment steps

Click the "Deploy to Azure" button at the beginning of this document


## Verify:

1.  Open up cloud shell
    
    Launch Cloud Shell from the top navigation of the Azure portal.
    
    ![CloudShell](https://docs.microsoft.com/en-us/azure/cloud-shell/media/quickstart/shell-icon.png)
  
2.  Configure kubectl

        az aks get-credentials --resource-group MyResourceGroup --name MyAKSCluster --overwrite-existing
    
3.  The initial deploy will have to download the container which takes about 10 minutes.  Verify its finished downloading the container:

		kubectl describe pod profisee-0 #check status and wait for "Pulling" to finish

4.  Container can be accessed with the following command:
    
        kubectl exec -it profisee-0 powershell

5.  System logs can be accessed with the following command:

		#Configuration log
		Get-Content C:\Profisee\Configuration\LogFiles\SystemLog.log
		#Authentication service log
		Get-Content C:\Profisee\Services\Auth\LogFiles\SystemLog.log
		#WebPortal Log
		Get-Content C:\Profisee\WebPortal\LogFiles\SystemLog.log
		#Gateway log
		Get-Content C:\Profisee\Web\LogFiles\SystemLog.log

6.  Goto Profisee Platform web portal
	- http(s)://app.company.com/profisee
