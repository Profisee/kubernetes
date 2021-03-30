# Deploy Profisee platform on to AWS Elastic Kubernetes services (EKS)

This explains the process to deploy the Profisee platform onto a new AWS EKS cluster

## Prerequisites

1.  License
    - Profisee license associated with the dns for the environment
    - ACR username, password and token

2.  Https certificate and the private key
			
3.  Choose your AWS region you want to use eg us-east-1

4.  SQL Server
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
		- Defaults for the rest of the options
		- Wait for database to be available
	- CLI sample: aws rds create-db-instance --engine sqlserver-ex --db-instance-class db.t3.small --db-instance-identifier profiseedemo --master-username sqladmin --master-user-password Password123 --allocated-storage 20
    	
5.  Create EBS volume - must be created in the same region/zone as the eks cluster
    - EBS volume - https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-creating-volume.html

	    - https://console.aws.amazon.com/ec2
		- Click Volumes under Elastic Block Store on left
		- Click create volume
		- Choose volume type and size
		- Choose Availability zone, make sure its in the same zone as the EKS cluster
		- Click Create Volume
		- When its finished creating, note the volume id
	- CLI sample:  aws ec2 create-volume --volume-type gp2 --size 1 --availability-zone us-east-1a --region us-east-1
    
6. Configure environment with required tools
	- Use aws cloudshell 
	  - https://dev.to/aws-builders/setting-up-a-working-environment-for-amazon-eks-with-aws-cloudshell-1nn7
	- Use local computer - no cloudshell - https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html
	  - Install aws cli - https://awscli.amazonaws.com/AWSCLIV2.msi
	  - Install eksctl - https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html
	  - Install kubectl - https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html
          - Setup IAM - https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-creds

7.  Configure DNS	
    - Choose a DNS host name that you want to use eg:  profiseemdm.mycompany.com
    - Register that hostname in your DNS provider with a CNAME that points to xxxxxx.elb.<region>.amazonaws.com (this will be updated later.
      

## Deployment

1.  Make cluster.yaml and upload to cloudshell.
	- Download the cluster.yaml
            	
			curl -fsSL -o cluster.yaml https://raw.githubusercontent.com/profisee/kubernetes/master/AWS-EKS-CLI/cluster.yaml;
		
	- Change the name, region and availabilityzones
	- Change the instance type(s) to fit your needs.  https://aws.amazon.com/ec2/pricing/on-demand/
	- For more complex deployments, including networking vpc and subnet configurations see https://eksctl.io/usage/schema/
    
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
    
        kubectl get services nginx-nginx-ingress-controller --namespace profisee
        #Note the external-ip and update the DNS hostname you created earlier and have it point to it (xxxxxx.elb.<region>.amazonaws.com)

4.  Configue Authentication provider
	- Create/configure an auth provider in your auth providr of choice.  eg Azure Active Directory, OKTA
	- Register redirect url http(s)://profiseemdm.mycompany.com/Profisee/auth/signin-microsoft
	- Note the clientid, secret and authority url.  The authority url for AAD is https://login.microsoftonline.com/{tenantid}

5.  Create Profisee Settings.yaml
    - Fetch the Settings.yaml template, download the yaml file so you can edit it locally
      
            curl -fsSL -o Settings.yaml https://raw.githubusercontent.com/profisee/kubernetes/master/AWS-EKS-CLI/Settings.yaml;
    - Update the values
    - Upload to cloudshell    

6.  Install Profisee

            helm repo add profisee https://profisee.github.io/kubernetes
            helm uninstall --namespace profisee profiseeplatform
            helm install --namespace profisee profiseeplatform profisee/profisee-platform --values Settings.yaml

# Verify and finalize:

1.  The initial deploy will have to download the container which takes about 10 minutes.  Verify its finished downloading the container:

	    #check status and wait for "Pulling" to finish
	    kubectl --namespace profisee describe pod profisee-0

2.  View the kubernetes logs and you will see that it fails the first time as it cannot talk to the sql server.

		kubectl logs profisee-0 --namespace profisee
		
3.  Update the sql security group to allow the container ip in
	- Connect to container 
	
			kubectl exec -it profisee-0 powershell
			
	- Get oubound ip and make note of it
	
			Invoke-RestMethod http://ipinfo.io/json | Select -exp ip
			
	- Click on sql instance
	- Click on VPC security group
	- Inbound rules
	- Edit inbound rules
	- Add MSSQL for outbound IP of cluster

4.  Remote back into the container and run ./setup.ps1
    
        kubectl --namespace profisee exec -it profisee-0 powershell
		./Setup.ps1

5.  Make sure it succeeds
	
6.  Voila, goto Profisee Platform web portal
	- http(s)://FQDNThatPointsToClusterIP/Profisee
