# Deploying Profisee Platform on AKS using the ARM template


## Prerequisites

Please **DO** review the guide and links below **before** you run the Azure ARM template. We have a pre-requisites script that runs before the deployment to check on the permissions needed.

Click [here](https://support.profisee.com/wikis/2022_r2_support/deploying_the_AKS_cluster_with_the_arm_template) for a detailed deployment guide for Profisee ver. 2022R2 and [here](https://support.profisee.com/lms/courseinfo?id=00u00000000002b00aM&mode=browsecourses) for video training course and slide deck.


Here's **what** you will need. You will need a license tied to the DNS URL that will be used by the environment (ex. customer.eastus2.cloudapp.azure.com OR YourOwnEnvironment.Customer.com) This license can be acquired from [Profisee Support](https://support.profisee.com/aspx/ProfiseeCustomerHome). 

Here's **what** will be deployed, or used if available, by the ARM template:
1. An AKS Cluster with a **publicly** accessible Management API.
2. Two Public IPs for Ingress and Egress.
3. A Load Balancer needed for Nginx.
4. A SQL Server, or we'll use one that you already have. You can either pre-create the database or let the Managed Identity create one for you.
5. A Storage account, or use one that you already have. If you precreate the storage account, please make sure to precreate the files share that you'd like to use.
6. A DNS entry into a zone, assuming the necessary permissions are there. If you use external DNS, you'd have to update/create the record to match the Egress IP.
7. A free Let's Encrypt certificate, if you choose that option. Please be aware that if you plan on using your own domain with Let's Encrypt you'll need to make sure that if there is a [CAA record set](https://letsencrypt.org/docs/caa/) on your domain it allows Let's Encrypt as the Issuing Authority.

Here's **how** it will be deployed. You must have a Managed Identity created to run the deployment. This Managed Identity must have the following permissions ONLY when running a deployment. After it is done, the Managed Identity can be deleted. Based on your ARM template choices, you will need some or all of the following permissions assigned to your Managed Identity:
1. **Contributor** role to the Resource Group where AKS will be deployed. This can either be assigned directly to the Resource Group OR at Subscription level. **Note:** If you want to allow the Deployment Managed Identity to create the resource group for you, then this permission would have to be at Subscription level. 
2. **DNS Zone Contributor** role to the particular DNS zone where the entry will be created OR **Contributor** role to the DNS Zone Resource Group.This is needed only if updating DNS hosted in Azure. To follow best practice for least access, the DNS Zone Contributor on the zone itself is the recommended option.
3. **Application Administrator** role in Azure Active Directory, so the Application registration can be created by the Deployment Managed Identity and the required permissions can be assigned to it.
4. **Managed Identity Contributor** and **User Access Administrator** at the Subscription level. These two are needed in order for the ARM template Deployment Managed Identity to be able to create the Key Vault specific Managed Identity that will be used by Profisee to pull the values stored in the Key Vault, as well as to assign the AKSCluster-agentpool the Managed Identity Operator role (to the Resource and Infrastructure Resource groups) and Virtual Machine Operator role (to the Infrastructure Resource group). If Key Vault will not be used, these roles are not required.
5. **Key Vault requirements**. If you are using a Key Vault, please make sure that your Access Policy page has a checkmark on "Azure Resource Manager for template deployment". Otherwise, MS will not be able to validate the ARM template's access against your Key Vault and will result in validation failure in the ARM template before it begins deployment.
6. **Purview Integration requirements**. If Profisee will be configured to integrate with Microsoft Purview, a Purview specific Application Registration will need to be created and have the **Collections Admin** and **Data Curator Role** assigned in the Purview account. It will also have to be assigned the User.Read **delegated** permission as well as the User.Read.All, Group.Read.All and GroupMember.Read.All **application** permissions (these 3 required Global Admin consent). During the ARM template deployment you will now have to provide the Purview collection friendly name, as seen in the Purview web portal, regardless if this is a sub-collection or the root collection of Purview. 


## Upgrade instructions

For customers upgrading **from** v2022**R1** and earlier. There are two changes that require careful consideration:
1. Purview Collections integration necessitated changes in the ARM template, container and deployment templates. Please **DO** review the upgrade instructions posted below **before** you start the upgrade process.
2. History tables improvements - you will need to run this immediately **after** the upgrade to 2022**R2**, one time **only**. 

Please read through the upgrade instructions both here and in our Support portal and prepare for the upgrade process. The instructions below are combined for both Purview Collections and the History table improvements. 

For customers who do **NOT** use Purview.
1. Connect to your cluster from the Azure portal or powershell. For customers running Private PaaS please connect to your jumpbox first, then connect via powershell or Lens.
2. Run the following commands (if you do not have the repo added that would be the first step):  
helm -n profisee repo add profisee https://profisee.github.io/kubernetes  
helm repo update  
helm upgrade -n profisee profiseeplatform profisee/profisee-platform --reuse-values --set image.tag=2022r2.0  
kubectl logs -n profisee profisee-0 -f #this will allow you to follow the upgrade as it is happening  
3. This will upgrade your installation to version 2022r2.0 while keeping the rest of the values.
4. To run the Histroy tables upgrade please follow the steps as outlined [here](https://support.profisee.com/wikis/release_notes/upgrade_considerations_and_prerequisites)
    
For customers who **DO** use Purview.
1. Connect to your cluster from the Azure portal or powershell. For customers running Private PaaS please connect to your jumpbox first, then connect via powershell or Lens.
2. Locate your Purview collection Id by visiting your MS Purview Governance Portal. Go to the collection where you would like Profisee to deploy to. Your URL will look like so: web.purview.azure.com/resource/**YourPurviewAccountName**/main/datasource/collections?collection=**ThisIsTheCollectionId**&feature.tenant=**YourAzureTenantId**
3. Run the following commands (if you do not have the repo added that would be the first step):  
helm -n profisee repo add profisee https://profisee.github.io/kubernetes  
helm repo update  
helm upgrade -n profisee profiseeplatform profisee/profisee-platform --reuse-values --set cloud.azure.purview.collectionId=YourCollectionId --set image.tag=2022r2.0  
kubectl logs -n profisee profisee-0 -f #this will allow you to follow the upgrade as it is happening  
4. This will upgrade your installation to version 2022r2.0 and provide the required collection Id while keeping the rest of the values. Failure to provide the collection Id would result in a failed upgrade.
5. To run the Histroy tables upgrade please follow the steps as outlined [here](https://support.profisee.com/wikis/release_notes/upgrade_considerations_and_prerequisites)


## Deployment steps

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2FcreateUIDefinition.json)

## Troubleshooting

All troubleshooting is in the [Wiki](https://github.com/profisee/kubernetes/wiki)

