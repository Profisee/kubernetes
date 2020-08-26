# Deploy Profisee platform on to Google Cloud Platform (GCP) Kubernetes

This explains the process to deploy the Profisee platform onto a new GCP Kubernetes cluster

## Prerequisites

1.  License
    - Profisee license associated with the dns for the environment
    - Token for access to the profisee container

2.  Https certificate including the private key

3.  SQL Server
    - GCP SqlServer instance - https://cloud.google.com/sql-server#section-4
    - Make sure the SQL Server is accessable by the cluster

4.  File Share
    - Create https://cloud.google.com/filestore/docs/accessing-fileshares
	- More docs https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes
        
 
## Deployment

1.  Open cloud shell
	- Goto GCP console - https://console.cloud.google.com/
	- Open up cloud shell - https://cloud.google.com/shell/docs/using-cloud-shell
    
2.  Create the main cluster
    
        gcloud container clusters create mycluster --cluster-version=1.16 --enable-ip-alias --num-nodes=3 --region us-east1-b
	- To save costs you can use the --preemptible flag https://cloud.google.com/blog/products/containers-kubernetes/cutting-costs-with-google-kubernetes-engine-using-the-cluster-autoscaler-and-preemptible-vms		
	

3.  Add windows node pool
	- VM sizing https://cloud.google.com/compute/vm-instance-pricing
    
        	gcloud container node-pools create windows-pool --cluster=mycluster --image-type=WINDOWS_LTSC --no-enable-autoupgrade --machine-type=n1-standard-2 --region us-east1-b
	
	- To save costs you can use the --preemptible flag https://cloud.google.com/blog/products/containers-kubernetes/cutting-costs-with-google-kubernetes-engine-using-the-cluster-autoscaler-and-preemptible-vms

3.  Install nginx

            helm repo add stable https://kubernetes-charts.storage.googleapis.com/;
            #get the nginx settings for gcp
            curl -fsSL -o nginxSettingsGCP.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/GCP-CLI/nginxSettingsGCP.yaml;
            helm install nginx stable/nginx-ingress --values nginxSettingsGCP.yaml
    
3.  Get nginx IP and update DNS
    
        kubectl get services nginx-nginx-ingress-controller
        #Note the external-ip and you need to create a A record in dns to point to it

4.  Create Profsiee Settings.yaml
    - Fetch the Settings.yaml template
      
            curl -fsSL -o Settings.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/GCP-CLI/Settings.yaml;
    - Update the values
    
			sqlServer: 
			    name: "Sql server fully qualified domain name"
			    databaseName: "Database name"
			    userName: "Sql username"
			    password: "Sql password"
			profiseeRunTime:
			    adminAccount: "Email/account of the first super user who will be registered with Profisee, who will be able to logon and add other users."
			    fileRepository:
				userName: "File repository username"
				password: "File repository password/access key"
				logonType: "NewCredentials"
				location: "File repository unc path eg: \\\\google.ip.address\\profisee"
			    externalDnsUrl: ""
			    externalDnsName: "web url to profisee endpoint eg: eks.mycompany.com"
			    oidc:
				name: "Authority name eg: Google"
				authority: "Authority url  eg: https://accounts.google.comt"
				clientId: "Authority client id eg" acbdefghijklmnop"
				clientSecret: "thisisasecret"
				usernameClaim: "Authority username claim name.  eg: http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
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

2.  System logs can be accessed within the container with the following command:
    
        Get-Content C:\Profisee\Configuration\LogFiles\SystemLog.log
	


