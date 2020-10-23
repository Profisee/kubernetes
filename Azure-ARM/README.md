# Deploy Profisee platform on to AKS using ARM template

'Lightning' deployment of the Profisee platform.  Use this for a brand new deplyment.  Https via Let's Encrypt.  Azure DNS (abc.eastus.cloudapps.azure.com).  New sql and storage repositories.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeploylightning.json)

'Lightning plus' deployment of the Profisee platform. Use this for a brand new deplyment and you want to use your own dns and https certificates.  New sql and storage repositories.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeploylightningplus.json)

'Quick' deployment of the Profisee platform. Use this is you have existing sql and/or storage repositories.  Https via Let's Encrypt.  Azure DNS (abc.eastus.cloudapps.azure.com).  New or existing sql and storage repositories.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeployquick.json)

'Quick plus' deployment of the Profisee platform. Use this is you have existing sql and/or storage repositories and you want to use your own dns and https certificates.  New or existing sql and storage repositories.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeployquickplus.json)

'Advanced' deployment of the Profisee platform.  Use this if you need custom networking and or kubernetes settings and you want to use your own dns and https certificates.  New or existing sql and storage repositories.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeployadvanced.json)

'Legacy' deployment of the Profisee platform. Use this if you are using a license prior to the 2020R2 rlease.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeploylegacy.json)

## Prerequisites

1.  Managed Identity
    - A user assigned managed identity configured ahead of time.  The managed identity must have Contributor role for the resource group, and the DNS zone resource group if updating DNS.  This can be done by assigning the contributor role to each individual resource group, or assigning the subscription level resource group.  If creating an Azure Active Directory application registration, the managed identity must have the Application Developer role assigned to it.  https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-manage-ua-identity-portal
2.  License
    - Profisee license associated with the dns for the environment
    - Token for access to the profisee container
3.  Https certificate including the private key

## Deployment steps

Click the "Deploy to Azure" button under the deployment option you want to use

## Troubleshooting

All troubleshooting is in the [Wiki](https://github.com/profisee/kubernetes/wiki)
