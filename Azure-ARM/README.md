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


## Trouble shooting

### Install Lens (Kubernetes IDE)

Main website https://k8slens.dev

Install the latest https://github.com/lensapp/lens/releases/latest

#### Add AKS cluster to Lens

	Go to Azure portal, open cloud shell

	Run this to "configure" kunectl
	az aks get-credentials --resource-group MyResourceGroup --name MyAKSCluster --overwrite-existing
	
	Get contents of kube.config
	run kubectl config view --minify --raw
	copy all the out put of that command (select with mouse, right click copy)
	
	Go to Lens
	Click big plus (+) to add a cluster
	Click paste as text
	Goto select contect dropdown and choose the cluster
	Click outside the dropdown area
	Click "Add Cluster(s)"
	Wait for it to connect and now Lens is connected to that aks cluster.
	
#### Connect to pod (container)

	In Lens, choose workloads, then pods
	Click on pod - profisee-(x)
	Click on the "Pod Shell" left icon in top blue nav bar.  This will "connect" you to the container
	Now in the terminal window (bottom), you are "connected" to the pod (container)
#### Restart Profisee service and IIS in pod (container)

	#Connect to pod if not already connected
	iisreset
	Restart-Service Profisee
	
	
#### Replace license 

	Download the Settings.Yaml file which is located in the generated storage account.  
		Download from generated storage account 
		Click on generated storage account in Resouce group, then File shares, then the generated file share name, then on azscriptinput 
		Click Settings.yaml, then download 
		Edit the file and replace the value for licenseFileData: 

	Upload to cloud drive 
		From cloud shell window click the Upload/Download file button in menu  
		Upload 
		Find the file you just downloaded it and click open 
		Wait for it to say complete (bottom right of shell window) 

	Uninstall profisee and reinstall 
		helm repo add profisee https://profisee.github.io/kubernetes 
		helm uninstall profiseeplatform2020r1 
		helm install profiseeplatform2020r1 profisee/profisee-platform --values Settings.yaml 

	Connect to container and make sure the config process has no errors 
		kubectl exec -it profisee-0 powershell 
		Get-Content C:\Profisee\Configuration\LogFiles\SystemLog.log 

#### Base 64 encode a string - All secrets are base 64 encoded

	$B64String =[Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("OrigString")) 
	write-host $B64String 
