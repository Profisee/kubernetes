# Deploy Profisee platform on to EKS (Amazon Elastic Kubernetes services)

This explains the process to deploy the Profisee platform onto a new AWS EKS clsuter

## Deployment steps

###Pre reqs

###Create cluster.yaml
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

#setup ami
aws configure
AWS Access Key ID [None]: XXXX
AWS Secret Access Key [None]: XXXX
Default region name [None]: us-east-1
Default output format [None]: json

#Create the cluster
eksctl create cluster -f cluster.yaml --install-vpc-controllers --timeout 30m --verbose=4

#connect kubectl
aws eks --region us-east-1 update-kubeconfig --name ChuckCluster

#Install nginx
helm repo add stable https://kubernetes-charts.storage.googleapis.com/;
#get the nginx settings for aws, note its different than azure/google
curl -fsSL -o nginxSettings.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/AWS-EKS-CLI/nginxSettingsAWS.yaml;
helm install nginx stable/nginx-ingress --values nginxSettingsNLB.yaml

#get ip
kubectl get services nginx-nginx-ingress-controller

#note the external-ip and you need to create a cname record in dns to point to it (xxxxxx.elb.us-east-1.amazonaws.com)

#Get the Settings.yaml template
curl -fsSL -o Settings.yaml https://raw.githubusercontent.com/Profisee/kubernetes/master/AWS-EKS-CLI/Settings.yaml;
#Update all the values

#Install Profisee
helm repo add profisee https://profisee.github.io/kubernetes
helm uninstall profiseeplatform2020r1
helm install profiseeplatform2020r1 profisee/profisee-platform --values Settings.yaml

