# Deploy Profisee platform on to AKS using ARM template

This ARM template deploys Profisee platform into a Azure Kubernetes Service cluster.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fprofisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2FcreateUIDefinition.json)

## Prerequisites

1.  Managed Identity
    - A user assigned managed identity configured ahead of time.  The managed identity must have Contributor role for the resource group, and the DNS zone resource group if updating Azure DNS.  This can be done by assigning the contributor role to each individual resource group, or assigning the subscription level resource group.  If creating an Azure Active Directory application registration, the managed identity must have the Application Developer role assigned to it.  Click [here](https://support.profisee.com/wikis/2020_r2_support/planning_your_managed_identity_configuration) for more information.
2.  License
    - Profisee license associated with the dns for the environment.
    
## Deployment steps

Click the "Deploy to Azure" button at the beginning of this document.

## Troubleshooting

All troubleshooting is in the [Wiki](https://github.com/profisee/kubernetes/wiki)
