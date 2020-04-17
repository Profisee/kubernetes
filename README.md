# **<span class="underline">AKS High-Level Steps</span>**

The following is a step-by-step tutorial of deploying an Azure
Kubernetes Service container. On this container, the Profisee Platform
is installed and configured.

# Prerequisites:

1)  Azure CLI

2)  AKS preview extension for Azure CLI

3)  Chocolatey

4)  Kubernetes-Helm

# Setup:

## A – GitHub Repository

Clone the following GitHub repository to your local machine:

  - <https://github.com/Profisee/profisee.github.io>

## B - Certificates

1.  Set the TLS certificate value in Values.yaml

2.  Set the TLS key value in Values.yaml

## C - Set the Azure AD redirect URI

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

##  D - Set variables in DeployAKS.ps1

The following properties must be set:

  - resourceGroupName

  - resourceGroupLocation

  - domainNameResourceGroup

  - domainName

  - hostName

  - azureClientId (value will be ID copied in step B-10)

  - azureClientSecret (if applicable)

  - azureTennantName

  - adminAccountForPlatform

# Run:

1.  Run the powershell script: DeployAKS.ps1

2.  Wait approx. 20 mins

# Verify:

1.  Container can be accessed with the following command:
    
        kubectl exec -it profisee-0 powershell

2.  System logs can be accessed with the following command:
    
        Get-Content C:\\Profisee\\Configuration\\LogFiles\\SystemLog.log
