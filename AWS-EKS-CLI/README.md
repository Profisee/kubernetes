# Deploy Profisee platform on to EKS (AWS Elastic Kubernetes services)

This explains the process to deploy the Profisee platform onto a new AWS EKS clsuter

## Prerequisites

1.  License
    - Profisee license associated with the dns for the environment
    - Token for access to the profisee container

2.  Https certificate including the private key

3.  SQL Server
    - AWS RDS instance - https://aws.amazon.com/getting-started/hands-on/create-microsoft-sql-db/
    - Make sure the SQL Server is accessable by the EKS cluster

4.  File Share
    - Create storage gateway (File via EC2) - https://docs.aws.amazon.com/storagegateway/latest/userguide/create-gateway-file.html
    - Create file share (SMB) - https://docs.aws.amazon.com/storagegateway/latest/userguide/CreatingAnSMBFileShare.html
    
5.  Credentials
    - Setup IAM - https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-creds
    
		    aws configure
		    AWS Access Key ID [None]: XXXX
		    AWS Secret Access Key [None]: XXXX
		    Default region name [None]: us-east-1
		    Default output format [None]: json
      

## Deployment

1.  Make cluster.yaml change the instance type to fit your needs.  https://aws.amazon.com/ec2/pricing/on-demand/

            apiVersion: eksctl.io/v1alpha5
            kind: ClusterConfig
            metadata:
              name: MyCluster
              region: us-east-1
              version: '1.17'  
            managedNodeGroups:
              - name: linux-ng
                instanceType: t2.large
                minSize: 1

            nodeGroups:
              - name: windows-ng
                instanceType: m5.xlarge
                minSize: 1
                volumeSize: 100
                amiFamily: WindowsServer2019FullContainer
    
2.  Create the EKS Clusterr
    
        eksctl create cluster -f cluster.yaml --install-vpc-controllers --timeout 30m

3.  Configure kubectl
    
        aws eks --region us-east-1 update-kubeconfig --name ChuckCluster

3.  Install nginx

            helm repo add stable https://kubernetes-charts.storage.googleapis.com/;
            #get the nginx settings for aws, note its different than azure/google
            curl -fsSL -o nginxSettings.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/AWS-EKS-CLI/nginxSettingsAWS.yaml;
            helm install nginx stable/nginx-ingress --values nginxSettingsNLB.yaml
    
3.  Get nginx IP
    
        kubectl get services nginx-nginx-ingress-controller
        #Note the external-ip and you need to create a cname record in dns to point to it (xxxxxx.elb.us-east-1.amazonaws.com)

4.  Create Profsiee Settings.yaml
    - Fetch the Settings.yaml template
      
            curl -fsSL -o Settings.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/AWS-EKS-CLI/Settings.yaml;
    -Update all the values
    
		sqlServer: 
		    name: "Sql server fully qualified domain name"
		    databaseName: "Database name"
		    userName: "Sql username"
		    password: "Sql password"
		profiseeRunTime:
		    adminAccount: "Email/account of the first super user who will be registered with Profisee, who will be able to logon and add other users."
		    fileRepository:
			userName: "File repository username eg: abc-12345\\smbguest"
			password: "File repository password"
			logonType: "NewCredentials"
			location: "File repository unc path eg: \\\\abc-12345.compute-1.amazonaws.com\\profisee"
		    externalDnsUrl: ""
		    externalDnsName: "web url to profisee endpoint eg: eks.mycompany.com"
		    oidc:
			name: "Authority name eg: Okta"
			authority: "Authority url  eg: https://mycompany.okta.com/oauth2/default"
			clientId: "Authority client id eg" acbdefghijklmnop"
			clientSecret: ""
			usernameClaim: "Authority username claim name.  eg: preferred_username"
			userIdClaim: "Authority userid claim name.  eg: http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"
			firstNameClaim: "Authority first name claim name.  eg: http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname"
			lastNameClaim: "Authority last name claim name.  eg: http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"
			emailClaim: "Authority email claim name.  eg: http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
		clusterNode:
		    limits:
		      cpu: 1000
		      memory: 10T
		    requests:
		      cpu: 1
		      memory: 1000M        
		image:
		    registry: "profisee.azurecr.io"
		    repository: "profisee2020r1"
		    tag: "1"
		    auth: |
			{
			   "auths":{
			      "profisee.azurecr.io":{
				 "username":"Username supplied by Profisee support",
				 "password":"Password supplied by Profisee support",
				 "email":"support@profisee.com",
				 "auth":"Token supplied by Profisee support"
			      }
			   }
			}
		licenseFileData: License string provided by Profisee support

		oidcFileData: |
		    {      
		    }
		tlsCert: |
		    -----BEGIN CERTIFICATE-----
		    Add certificate string with opening and closing tags like this
		    -----END CERTIFICATE-----
		tlsKey: |
		    -----BEGIN PRIVATE KEY-----
		    Add certificate key string with opening and closing tags like this
		    -----END PRIVATE KEY-----

5.  Install Profisee

            helm repo add profisee https://profisee.github.io/kubernetes
            helm uninstall profiseeplatform2020r1
            helm install profiseeplatform2020r1 profisee/profisee-platform --values Settings.yaml
            
# Verify:

1.  The initial deploy will have to download the container which takes about 10 minutes.  Verify its finished downloading the container:

		kubectl describe pod profisee-0 #check status and wait for "Pulling" to finish

1.  Container can be accessed with the following command:
    
        kubectl exec -it profisee-0 powershell

2.  System logs can be accessed with the following command:
    
        Get-Content C:\Profisee\Configuration\LogFiles\SystemLog.log
	


