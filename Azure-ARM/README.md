# Deploying Profisee Platform on AKS using the ARM template


## Prerequisites

Please **DO** review the guide and links below **before** you run the Azure ARM template. We have a pre-requisites script that runs before the deployment to check on the permissions needed.

Click [here](https://support.profisee.com/wikis/2021_r3_support/deploying_the_AKS_cluster_with_the_arm_template) for a detailed deployment guide for Profisee ver. 2021R3 and [here](https://support.profisee.com/lms/courseinfo?id=00u00000000002b00aM&mode=browsecourses) for video training course and slide deck.


Here's **what** you will need. You will need a license tied to the DNS URL that will be used by the environment (ex. customer.eastus2.cloudapp.azure.com OR YourOwnEnvironment.Customer.com) This license can be acquired from [Profisee Support](https://support.profisee.com/aspx/ProfiseeCustomerHome). 

Here's **what** will be deployed, or used if available, by the ARM template:
1. An AKS Cluster with a **publicly** accessible Management API.
2. Two Public IPs for Ingress and Egress
3. A Load Balancer needed for Nginx
4. A SQL Server, or use one that you already have. You can either pre-create the database or let the MI create one for you.
5. A Storage account, or use one that you already have.
6. A DNS entry into a zone, assuming the necessary permissions are there. If using external DNS, you'd have to update/create the record with the Egress IP.

Here's **how** it will be deployed. You must have a Managed Identity created to run the deployment. This Managed Identity must have the following permissions ONLY when running a deployment. After it is done, the Managed Identity can be deleted. Based on your ARM template choices, you will need some or all of the following permissions assigned to your Managed Identity:
1. **Contributor** role to the Resource Group where AKS will be deployed. This can either be assigned directly to the Resource Group OR at Subscription level down.
2. **DNS Zone Contributor** role to the particular DNS zone where the entry will be created OR **Contributor** role to the DNS Zone Resource Group. This is needed only if updating DNS hosted in Azure. 
3. **Application Administrator** role in Azure Active Directory so the required permissions that are needed for the Application Registration can be assigned.
4. **Managed Identity Contributor** and **User Access Administrator** at the Subscription level. These two are needed in order for the ARM template Managed Identity to be able to create the Key Vault specific Managed Identity that will be used by Profisee to pull the values stored in the Key Vault.
5. **Data Curator Role** added for the Purview account for the Purview specific Application Registration.

    
## Deployment steps

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2FcreateUIDefinition.json)

## Troubleshooting

All troubleshooting is in the [Wiki](https://github.com/profisee/kubernetes/wiki)
