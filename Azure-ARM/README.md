# Deploy Profisee platform on to AKS using ARM template

This ARM template deploys Profisee platform into a new Azure Kubernetes service cluster.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FProfisee%2Fkubernetes%2Fmaster%2FAzure-ARM%2Fazuredeploy.json)

## Prerequisites

1.  Managed Identity
    - You must have a user assigned managed identity configured ahead of time.  The managed identity must have Contributor role for the resource group, and the DNS zone resource group.  If creating an Azure Active Directory application registration, the managed identity must have the Application Developer role assigned to it.  https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-manage-ua-identity-portal
2.  License
    - Profisee license associated with the dns for the environment
    - Token for access to the profisee container

## Deployment steps

Click the "Deploy to Azure" button at the beginning of this document
