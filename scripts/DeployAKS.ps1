###############
#Pre-Reqs     #
###############
#Set execution policy
#Set-ExecutionPolicy Unrestricted

##Install AZ CLI - Must be 2.5 or higher
#Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi

#Install choco - needed for Helm
#Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
#choco install kubernetes-helm

#Login to Azure
#az login

###############
#Pre-Run      #
###############
#set variables in ps1
#set values for certs in Values.yaml

################################
# Run 						   #
################################
######Variables to change######
$createResourceGroup = $true
$resourceGroupName = "MyAKS"
$resourceGroupLocation = "eastus2"

###SQL###
$createSqlServer = $true
$sqlServerResourceGroup = $resourceGroupName
$sqlServerName = $resourceGroupName + "sql"
$sqlDatabaseName = "Profisee"
$sqlUserName = "serveradmin"
$sqlPassword = "P@ssw0rd33#$"

###DNS###
$createDNSRecord = $true
$domainNameResourceGroup = "domainRG"
$domainName = "domain.com"
$hostName = "aks"

##File Repository###
$createFileRepository = $true
$storageAccountName = $resourceGroupName + "files" 
$storageShareName = "files"

###Azure AD App Registration###
$createAppInAzureAD = $true
$azureClientName = "My Identity Server"
$azureClientId = ""
$azureClientSecret = ""

###VM Sizes###
$clusterVmSizeForLinux = "Standard_B2s"
$clusterVmSizeForWindows = "Standard_B4ms"

###AKS Version###
$kubernetesVersion = "1.17.3"

###Profisee platform###
$adminAccountForPlatform = "MyEmail@domain.com"

######Variables that dont need to change######
$aksClusterName = "MyAKSCluster"
$staticIpOutName = "AKSStaticOutIP"
$staticIpInName = "AKSStaticInIP"

######DO NOT CHANGE######
$externalDnsName = $hostName + "." + $domainName
$externalDnsUrl = "https://" + $externalDnsName
$resourceGroupNameForNodes = "MC_" + $resourceGroupName + "_" + $aksClusterName + "_" + $resourceGroupLocation

#create resource group
if($createResourceGroup)
{
	az group create --name $resourceGroupName --location $resourceGroupLocation
}

#create aks cluster node pool (linox)
az aks create --resource-group $resourceGroupName --name $aksClusterName --node-count 1 --enable-addons monitoring --kubernetes-version $kubernetesVersion --generate-ssh-keys --windows-admin-password P@ssw0rd1234! --windows-admin-username winadmin --vm-set-type VirtualMachineScaleSets --load-balancer-sku standard --network-plugin azure --node-vm-size $clusterVmSizeForLinux

#create static public ip for outbound usage - loadbalancer
az network public-ip create --resource-group $resourceGroupNameForNodes --name $staticIpOutName --sku Standard --allocation-method static
$publicOutIP = az network public-ip show -g $resourceGroupNameForNodes -n $staticIpOutName --query ipAddress --output tsv
$publicOutIPID = az network public-ip show -g $resourceGroupNameForNodes -n $staticIpOutName --query id --output tsv

#create static public ip for outbound usage - ingress controller
az network public-ip create --resource-group $resourceGroupNameForNodes --name $staticIpInName --sku Standard --allocation-method static
$publicInIP = az network public-ip show -g $resourceGroupNameForNodes -n $staticIpInName --query ipAddress --output tsv

#set ip of loadbalancer
az aks update --resource-group $resourceGroupName --name $aksClusterName --load-balancer-outbound-ips $publicOutIPID

#create windows node pool
az aks nodepool add --resource-group $resourceGroupName --cluster-name $aksClusterName --name npwin1 --os-type Windows  --node-count 1 --node-vm-size $clusterVmSizeForWindows

#get aks creds
az aks get-credentials --resource-group $resourceGroupName --name $aksClusterName --overwrite-existing

#add dns record to domain
if($createDNSRecord)
{
	az network dns record-set a delete -g $domainNameResourceGroup -z $domainName -n $hostName --yes
	az network dns record-set a add-record -g $domainNameResourceGroup -z $domainName -n $hostName -a $publicInIP --ttl 5
}

#create sql server - if needed
if($createSqlServer)
{
	az sql server create --resource-group $resourceGroupName --name $sqlServerName --location $resourceGroupLocation -u $sqlUserName -p $sqlPassword
}

#get the sql server
$sqlServerFQDN = az sql server show --resource-group $sqlServerResourceGroup --name $sqlServerName --query fullyQualifiedDomainName --output tsv

#create firewall rule for sql server, ip of aks cluster and ip of where this script is run
az sql server firewall-rule create --resource-group $sqlServerResourceGroup --server $sqlServerName.ToLower() --name "aks node ip" --start-ip-address $publicOutIP --end-ip-address $publicOutIP
$myIP = Invoke-RestMethod http://ipinfo.io/json | Select -exp ip
az sql server firewall-rule create --resource-group $sqlServerResourceGroup --server $sqlServerName.ToLower() --name "scripter ip" --start-ip-address $myIP --end-ip-address $myIP

#create storage account and file share - file repo for platform - if needed
if($createFileRepository)
{
	az storage account create --resource-group $resourceGroupName --name $storageAccountName.ToLower() --location $resourceGroupLocation
	$storageAccountKey = (az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query "[0].value")
	az storage share create --account-name $storageAccountName.ToLower() --account-key $storageAccountKey --name $storageShareName
}
$fileRepoUserName = "Azure\\" +  $storageAccountName.ToLower()
$fileRepoPath = "\\\\" + $storageAccountName.ToLower() + ".file.core.windows.net\\" + $storageShareName

#Azure AD Client registration
$azureAppReplyUrl = $externalDnsUrl + "/profisee/auth/signin-microsoft"
$azureTenantId = az account show --query tenantId --output tsv
$azureAuthorityUrl = "https://login.microsoftonline.com/" + $azureTenantId
if($createAppInAzureAD)
{
	az ad app create --display-name $azureClientName --reply-urls $azureAppReplyUrl
	$azureClientId = az ad app list --filter "displayname eq '$azureClientName'" --query '[0].appId'
}
az ad app update --id $azureClientId --add --reply-Urls $azureAppReplyUrl
#add a Graph API permission of "Sign in and read user profile"
az ad app permission add --id $azureClientId --api 00000002-0000-0000-c000-000000000000 --api-permissions 311a71cc-e848-46a1-bdf8-97ff7156d8e6=Scope
az ad app permission grant --id $azureClientId --api 00000002-0000-0000-c000-000000000000

#install nginx
helm repo add stable https://kubernetes-charts.storage.googleapis.com/ 
helm install nginx stable/nginx-ingress --values .\nginxValues.yaml --set controller.service.loadBalancerIP=$publicInIP
#helm uninstall nginx stable/nginx-ingress

#install profisee platform
helm repo add profisee https://profisee.github.io
helm install profiseeplatform2020r1 profisee/profisee-platform --values .\Values.yaml --set sqlServer.name=$sqlServerFQDN --set sqlServer.databaseName=$sqlDatabaseName --set sqlServer.userName=$sqlUserName --set sqlServer.password=$sqlPassword --set profiseeRunTime.fileRepository.userName=$fileRepoUserName --set profiseeRunTime.fileRepository.password=$storageAccountKey --set profiseeRunTime.fileRepository.location=$fileRepoPath --set profiseeRunTime.oidc.authority=$azureAuthorityUrl --set profiseeRunTime.oidc.clientId=$azureClientId --set profiseeRunTime.oidc.clientSecret=$azureClientSecret --set profiseeRunTime.adminAccount=$adminAccountForPlatform --set profiseeRunTime.externalDnsUrl=$externalDnsUrl --set profiseeRunTime.externalDnsName=$externalDnsName

#check status and wait for "Pulling" to finish
#kubectl describe pod profisee-0

#remote in and look
#kubectl exec -it profisee-0 powershell
 
#get config log
#Get-Content C:\Profisee\Configuration\LogFiles\SystemLog.log