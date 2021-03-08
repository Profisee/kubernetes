# Deploy Profisee platform on to AWS Elastic Kubernetes services (EKS)

This explains the process to deploy the Profisee platform onto a new AWS EKS cluster

## Prerequisites

1.  License
    - Profisee license associated with the dns for the environment

2.  Https certificate including the private key
	- Certificate
	
			-----BEGIN CERTIFICATE-----
			XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
			-----END CERTIFICATE-----
			
	- Key
	
			-----BEGIN PRIVATE KEY-----
			XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
			-----END PRIVATE KEY-----

			or

			-----BEGIN RSA PRIVATE KEY-----
			XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
			-----END RSA PRIVATE KEY-----
			
3.  SQL Server
    - AWS RDS instance - https://aws.amazon.com/getting-started/hands-on/create-microsoft-sql-db/
    	
		- Goto https://console.aws.amazon.com/rds
		- Click create database
		- Standard Create - Microsoft SQL Server
		- Edition - Choose what you want
		- Version - Choose (default should be fine)
		- Give sql server name as db intance identifier
		- Credentials
			- Master username - login name to use
			- Password - strong password
		- Size - Choose what you need
		- Storage - Defaults should be fine, probably no need for autoscaling
		- Connectivity
			- Public access yes (simpler to debug) - Change to fit your security needs when ready
		- Defaults for rest
		- Wait for database to be available
    	
	- Make sure the SQL Server is accessable by the EKS cluster
		- Click on sql instance
		- Click on VPC security group
		- Inbound rules
		- Edit inbound rules
		- Add MSSQL for outbound IP of cluster
		- To get outbound ip of cluster Deployment step #5 needs to be complete
			- Connect to container - kubectl exec -it profisee-0 powershell
			- get oubound ip - Invoke-RestMethod http://ipinfo.io/json | Select -exp ip

4.  Create EBS volume
    - aws ec2 create-volume --volume-type gp2 --size 80 --availability-zone us-east-1c --region us-east-1
    - https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-creating-volume.html
    
5. Configure environment with required tools
	- Use aws cloudshell - https://console.aws.amazon.com/cloudshell 
	  - https://dev.to/aws-builders/setting-up-a-working-environment-for-amazon-eks-with-aws-cloudshell-1nn7
	- Use local computer - no cloudshell
	  - https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html
	  - Install aws cli - https://awscli.amazonaws.com/AWSCLIV2.msi
	  - Install eksctl 
		- Install chocolately if you need it - https://chocolatey.org/install
		- Install eksctl - chocolatey install -y eksctl 
	  - Install kubectl
		- curl -o kubectl.exe https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.9/2020-08-04/bin/windows/amd64/kubectl.exe
		- Set path
			- Create a new directory for your command line binaries, such as C:\bin.
			- Copy the kubectl.exe binary to your new directory.
			- Edit your user or system PATH environment variable to add the new directory to your PATH.
			- Close your PowerShell terminal and open a new one to pick up the new PATH variable.
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
              version: '1.18'  
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
    
        aws eks --region us-east-1 update-kubeconfig --name MyCluster

3.  Install nginx for AWS

            helm repo add stable https://charts.helm.sh/stable;
            curl -o nginxSettingsAWS.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/AWS-EKS-CLI/nginxSettingsAWS.yaml;
            kubectl creaate namespace profisee
	    helm install nginx stable/nginx-ingress --values nginxSettingsAWS.yaml --namespace profisee
	    
	- Wait for the load balancer to be provisioned.  goto aws ec2/load balancing console and wait for the state to go from provisioning to active (3ish minutes)
    
3.  Get nginx IP
    
        kubectl get services nginx-nginx-ingress-controller
        #Note the external-ip and you need to create a cname record in dns to point to it (xxxxxx.elb.<region>.amazonaws.com)

4.  Create Profisee Settings.yaml
    - Fetch the Settings.yaml template
      
            curl -fsSL -o Settings.yaml https://raw.githubusercontent.com/Profiseedev/kubernetes/master/AWS-EKS-CLI/Settings.yaml;
    - Update the values
    
			sqlServer: 
			    name: "Sql server fully qualified domain name"
			    databaseName: "Database name"
			    userName: "Sql username"
			    password: "Sql password"
			profiseeRunTime:
			    useLetsEncrypt: false
			    adminAccount: "Email/account of the first super user who will be registered with Profisee, who will be able to logon and add other users."
			    fileRepository:
				accountName: ""
				userName: "user manager\\containeradministrator"
				password: ""
				logonType: "NewCredentials"
				location: "c:\\fileshare"
				fileShareName: ""
			    externalDnsUrl: "url to profisee endpoint eg: https://eks.mycompany.com"
			    externalDnsName: "web url to profisee endpoint eg: eks.mycompany.com"
			    oidc:
				name: "Authority name eg: Okta"
				authority: "Authority url  eg: https://mycompany.okta.com/oauth2/default"
				clientId: "Authority client id eg" acbdefghijklmnop"
				clientSecret: "Authority client secret"
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
			    repository: "profiseeplatform"
			    tag: "2021r1.0"
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
			cloud:
			    azure:
			      isProvider: false      
			    aws:
			      isProvider: true
			      ebsVolumeId: "volume id of existing ebs volume"
			    google:
			      isProvider: false

5.  Configue Authentication provider
	- Register redirect url http(s)://FQDNThatPointsToClusterIP/Profisee/auth/signin-microsoft
6.  Install Profisee

            helm repo add profisee https://profiseedev.github.io/kubernetes
            helm uninstall --namespace profisee profiseeplatform
            helm install --namespace profisee profiseeplatform profisee/profisee-platform --values Settings.yaml
            
# Verify:

1.  The initial deploy will have to download the container which takes about 10 minutes.  Verify its finished downloading the container:

		kubectl --namespace profisee describe pod profisee-0#check status and wait for "Pulling" to finish

1.  Container can be accessed with the following command:
    
        kubectl --namespace profisee exec -it profisee-0 powershell

2.  System logs can be accessed with the following command:
    
        Get-Content C:\Profisee\Configuration\LogFiles\SystemLog.log
	
3.  Goto Profisee Platform web portal
	- http(s)://FQDNThatPointsToClusterIP/Profisee
	


