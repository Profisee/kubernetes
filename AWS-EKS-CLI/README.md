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
    - Create storage gateway (file) - https://docs.aws.amazon.com/storagegateway/latest/userguide/create-gateway-file.html
    - Create file share (SMB) - https://docs.aws.amazon.com/storagegateway/latest/userguide/CreatingAnSMBFileShare.html
    
5.  Credentials
    - Setup IAM - https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-creds
    - aws configure
      AWS Access Key ID [None]: XXXX
      AWS Secret Access Key [None]: XXXX
      Default region name [None]: us-east-1
      Default output format [None]: json
      

## Deployment steps

1.  Make cluster.yaml

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
    - eksctl create cluster -f cluster.yaml --install-vpc-controllers --timeout 30m

3.  Configure kubectl
    - aws eks --region us-east-1 update-kubeconfig --name ChuckCluster

3.  Install nginx

            helm repo add stable https://kubernetes-charts.storage.googleapis.com/;
            #get the nginx settings for aws, note its different than azure/google
            curl -fsSL -o nginxSettings.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/AWS-EKS-CLI/nginxSettingsAWS.yaml;
            helm install nginx stable/nginx-ingress --values nginxSettingsNLB.yaml
    
3.  Get nginx IP
    - kubectl get services nginx-nginx-ingress-controller
    - Note the external-ip and you need to create a cname record in dns to point to it (xxxxxx.elb.us-east-1.amazonaws.com)

4.  Create Profsiee Settings.yaml
    - Fet the Settings.yaml template
      
            curl -fsSL -o Settings.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/AWS-EKS-CLI/Settings.yaml;
    -Update all the values

5.  Install Profisee

            helm repo add profisee https://profisee.github.io/kubernetes
            helm uninstall profiseeplatform2020r1
            helm install profiseeplatform2020r1 profisee/profisee-platform --values Settings.yaml
            
6.  Verify
    -Comming soon

