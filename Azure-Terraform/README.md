# Profisee Platform - Terraform Deployment for Azure

This directory contains Terraform configurations to deploy the Profisee Platform on Azure Kubernetes Service (AKS) with supporting infrastructure. This replaces the ARM template deployment with a more maintainable and version-controlled Infrastructure as Code approach.

## Overview

This Terraform configuration deploys:
- Azure Kubernetes Service (AKS) cluster with Linux and Windows node pools
- Azure SQL Server and Database
- Azure Storage Account with File Share
- **Log Analytics Workspace with comprehensive monitoring**
- **Diagnostic settings for all resources**
- **Azure Monitor for Containers integration**
- User-assigned Managed Identity
- Azure AD Application (optional)
- Role assignments and permissions

## Prerequisites

Before deploying, ensure you have:

1. **Terraform installed** (>= 1.0)
   ```powershell
   winget install HashiCorp.Terraform
   ```

2. **Azure CLI installed and authenticated**
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

3. **kubectl installed** (optional, for cluster management)
   ```powershell
   winget install Kubernetes.kubectl
   ```

4. **Helm installed** (optional, for Profisee deployment)
   ```powershell
   winget install Helm.Helm
   ```

5. **Required Azure permissions**: Your account needs the following permissions:
   - **Contributor** role on the subscription or resource group
   - **Application Administrator** role in Azure AD (if creating AD app)
   - **User Access Administrator** (for role assignments)
   - **Key Vault Administrator** (if using Key Vault integration)

## Version Requirements

| Tool | Minimum Version | Recommended | Notes |
|------|----------------|-------------|-------|
| Terraform | 1.0+ | 1.5+ | Uses modern provider syntax |
| Azure CLI | 2.30+ | Latest | Required for authentication |
| kubectl | 1.20+ | Latest | For AKS cluster management |
| Helm | 3.7+ | Latest | For Profisee deployment |
| PowerShell | 5.1+ | 7.3+ | For Windows deployment scripts |

## Compatibility

- **Azure Cloud**: Public, Government, and China clouds supported
- **Kubernetes**: Supports Kubernetes 1.24+ (AKS supported versions)
- **Operating Systems**: Windows 10/11, Linux, macOS
- **Terraform Providers**: 
  - azurerm ~> 3.80
  - azuread ~> 2.41
  - random ~> 3.4

## Quick Start

1. **Navigate to the Terraform directory**
   ```bash
   cd Azure-Terraform
   ```

2. **Copy and customize configuration**
   ```bash
   copy sample.tfvars terraform.tfvars
   ```
   Edit `terraform.tfvars` with your specific values:
   ```hcl
   resource_group_name            = "your-resource-group"
   profisee_admin_user_account    = "admin@yourcompany.com"
   profisee_license              = "your-license-key"
   profisee_web_app_name         = "profisee-app"
   sql_server_name               = "your-unique-sql-server"
   sql_server_password           = "YourSecurePassword123!"
   storage_account_name          = "youruniquestorage"
   storage_account_file_share_name = "profisee-fileshare"
   
   # Optional: Enable Azure Key Vault for secure secrets storage
   use_key_vault = "Yes"
   key_vault     = "profisee-keyvault-001"
   ```

3. **Deploy with Terraform**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```
   
   **Alternative: Use deployment scripts**
   ```powershell
   # Windows
   .\deploy.bat
   
   # Linux/Mac
   ./deploy.sh
   ```
   
   The deployment scripts automatically run `terraform init`, `plan`, and `apply` with proper error handling.

4. **Get AKS credentials and deploy Profisee**
   ```bash
   # Get AKS credentials
   az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw kubernetes_cluster_name)
   
   # Deploy Profisee using Helm
   helm repo add profisee https://profisee.github.io/kubernetes
   helm install profisee profisee/profisee-platform --namespace profisee --create-namespace
   ```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `resource_group_name` | Azure resource group name | `"profisee-rg"` |
| `profisee_admin_user_account` | Admin user email | `"admin@company.com"` |
| `profisee_license` | Profisee license key | `"your-license-key"` |
| `profisee_web_app_name` | Web application name | `"profisee-app"` |
| `sql_server_name` | SQL Server name (globally unique) | `"profisee-sql-server"` |
| `sql_server_password` | SQL Server admin password | `"YourSecurePassword123!"` |
| `storage_account_name` | Storage account name (globally unique) | `"profiseestorage"` |
| `storage_account_file_share_name` | File share name | `"profisee-fileshare"` |
| `use_key_vault` | Enable Key Vault for secrets | `"Yes"` or `"No"` |
| `key_vault` | Key Vault name (if enabled) | `"profisee-keyvault-001"` |

### Optional Configuration

- **Kubernetes Settings:**
  - `kubernetes_cluster_name`: AKS cluster name (default: "ProfiseeAKSCluster")
  - `kubernetes_linux_node_count`: Linux node count (default: 2)  
  - `kubernetes_windows_node_count`: Windows node count (default: 1)
  - VM sizes, networking settings, etc.

- **DNS and HTTPS:**
  - `dns_host_name`, `dns_domain_name`: For custom domain
  - `https_configure`, `use_lets_encrypt`: SSL certificate options

- **Azure Services:**
  - `use_key_vault`: Enable Azure Key Vault integration ("Yes" or "No")
  - `key_vault`: Key Vault name for secrets storage (when enabled)
  - `use_purview`: Enable Azure Purview integration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Resource Group                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │   AKS Cluster   │    │   SQL Server    │                │
│  │                 │    │                 │                │
│  │ • Linux Nodes   │    │ • Database      │                │
│  │ • Windows Nodes │    │ • Firewall      │                │
│  │ • RBAC Enabled  │    │ • AAD Auth      │                │
│  └─────────────────┘    └─────────────────┘                │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │ Storage Account │    │ Managed Identity│                │
│  │                 │    │                 │                │
│  │ • File Share    │    │ • Role Assign.  │                │
│  │ • Encrypted     │    │ • AKS Access    │                │
│  └─────────────────┘    └─────────────────┘                │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │  AD Application │    │   Key Vault     │                │
│  │   (Optional)    │    │   (Optional)    │                │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## Azure Key Vault Integration

This deployment supports optional Azure Key Vault integration for secure secrets management. When enabled, sensitive configuration values are stored in Azure Key Vault instead of plain text.

### Enabling Key Vault

To enable Key Vault integration, update your `terraform.tfvars`:

```hcl
use_key_vault = "Yes"
key_vault     = "profisee-keyvault-001"  # Must be globally unique
```

### What Gets Stored in Key Vault

When Key Vault is enabled, the following secrets are automatically stored:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `sql-admin-password` | SQL Server administrator password | `YourSecurePassword123!` |
| `sql-connection-string` | Complete SQL connection string | `Server=tcp:...` |
| `storage-account-key` | Storage account primary access key | `base64-encoded-key` |
| `storage-connection-string` | Storage account connection string | `DefaultEndpointsProtocol=https...` |
| `profisee-license` | Profisee platform license key | `your-license-key` |

### Key Vault Configuration

The Key Vault is configured with:

- **Access Policies**: Managed Identity has Get/List permissions
- **Network Access**: Can be restricted to virtual network (configurable)
- **Soft Delete**: Enabled for data protection (90-day retention)
- **Purge Protection**: Optional additional security layer
- **RBAC Integration**: Azure AD authentication for administrative access

### Accessing Secrets from AKS

The deployment configures the AKS cluster to access Key Vault secrets using:

1. **Azure Workload Identity**: Modern, secure authentication method
2. **Managed Identity**: Eliminates need for stored credentials
3. **CSI Secret Store Driver**: Mounts secrets as volumes in pods

Example pod configuration:
```yaml
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: profisee-workload-identity
  containers:
  - name: profisee-app
    volumeMounts:
    - name: secrets-store
      mountPath: "/mnt/secrets"
      readOnly: true
  volumes:
  - name: secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      parameters:
        secretProviderClass: "profisee-secrets"
```

### Key Vault Best Practices

**Security:**
- Use separate Key Vaults for different environments (dev/staging/prod)
- Enable diagnostic logging to monitor access patterns
- Implement least privilege access policies
- Regular audit of access permissions

**Operations:**
- Use descriptive names for secrets
- Implement secret rotation policies
- Monitor Key Vault capacity and throttling limits
- Set up alerts for unauthorized access attempts

**Cost Optimization:**
- Key Vault operations are charged per transaction
- Monitor usage through Azure Cost Management
- Consider consolidating secrets to reduce transaction costs

### Migration to Key Vault

If you have an existing deployment without Key Vault:

1. **Enable Key Vault** in `terraform.tfvars`:
   ```hcl
   use_key_vault = "Yes"
   key_vault     = "your-unique-keyvault-name"
   ```

2. **Apply Terraform changes**:
   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

3. **Update application configuration** to reference Key Vault secrets instead of environment variables

4. **Verify secret access**:
   ```bash
   # Check if secrets are accessible from AKS
   kubectl exec -it <pod-name> -- cat /mnt/secrets/sql-admin-password
   ```

### Troubleshooting Key Vault Issues

**Common Problems:**

1. **Access Denied Errors**:
   - Verify Managed Identity has proper Key Vault access policies
   - Check that Workload Identity is properly configured
   - Ensure CSI Secret Store Driver is installed

2. **Secret Not Found**:
   - Verify secret names match exactly (case-sensitive)
   - Check that secrets were properly created during deployment
   - Confirm Key Vault name is correct in configuration

3. **CSI Driver Issues**:
   - Verify the Azure Key Vault Provider for Secrets Store CSI Driver is installed
   - Check pod logs for detailed error messages
   - Ensure SecretProviderClass is properly configured

**Diagnostic Commands:**
```bash
# Check Key Vault access from AKS node
az keyvault secret show --vault-name <vault-name> --name sql-admin-password

# Verify CSI driver installation
kubectl get pods -n kube-system | grep secrets-store

# Check SecretProviderClass
kubectl describe secretproviderclass profisee-secrets
```

## Monitoring & Logging

This deployment includes comprehensive monitoring and logging capabilities through Azure Log Analytics:

### Log Analytics Workspace
- **Name**: `{profisee_web_app_name}-logs`
- **Retention**: 30 days (configurable)
- **SKU**: PerGB2018 (pay-as-you-go)
- **Integration**: Connected to all deployed resources

### Monitoring Coverage
- ✅ **AKS Cluster**: Azure Monitor for containers, pod/node metrics, Kubernetes events
- ✅ **SQL Database**: Query performance, errors, blocking, deadlocks, wait statistics
- ✅ **SQL Server**: Performance metrics and operational data
- ✅ **Storage Account**: Transaction metrics and capacity information
- ✅ **Storage Services**: Blob and File service operation logs (read/write/delete)

### Access Your Monitoring Data
After deployment, access monitoring through:
```bash
# Get Log Analytics workspace URL from Terraform output
terraform output log_analytics_workspace_id

# Or visit Azure Portal -> Log Analytics workspaces -> {workspace-name}
```

### Sample Monitoring Queries

**Container CPU Usage**:
```kusto
Perf
| where ObjectName == "K8SContainer" and CounterName == "cpuUsageNanoCores"
| summarize avg(CounterValue) by bin(TimeGenerated, 5m), InstanceName
```

**SQL Database Errors**:
```kusto
AzureDiagnostics
| where Category == "Errors"
| summarize count() by bin(TimeGenerated, 1h)
```

**Storage File Operations**:
```kusto
StorageFileLogs
| where OperationName in ("PutFile", "GetFile", "DeleteFile")
| summarize count() by bin(TimeGenerated, 1h), OperationName
```

**AKS Pod Status**:
```kusto
KubePodInventory
| summarize count() by PodStatus, bin(TimeGenerated, 5m)
```

### Monitoring Best Practices
- Review dashboards regularly for performance trends
- Set up alerts for critical metrics (CPU > 80%, memory > 90%)
- Monitor SQL database DTU consumption
- Track storage account capacity and IOPS
- Use Application Insights for application-level monitoring

## Security Features

This Terraform configuration implements security best practices:

- **Managed Identity**: Uses Azure Managed Identity for secure authentication
- **RBAC**: Implements Azure AD RBAC for AKS cluster  
- **Network Security**: Configures appropriate network policies
- **Encrypted Storage**: Enables encryption for storage accounts
- **SQL Security**: Configures Azure AD authentication for SQL Server
- **Key Vault Integration**: 
  - Optional integration for centralized secrets management
  - Workload Identity for secure pod-to-Key Vault authentication
  - CSI Secret Store Driver for mounting secrets as volumes
  - Soft delete and purge protection enabled
  - Access policies following principle of least privilege
- **Certificate Management**: Integration with Let's Encrypt for automated SSL certificates
- **Network Isolation**: Virtual network integration with private endpoints (configurable)
- **Audit Logging**: All Key Vault access and administrative actions are logged
- **Least Privilege**: All role assignments follow principle of least privilege

## Post-Deployment

After successful deployment:

1. **Get AKS credentials**:
   ```bash
   az aks get-credentials --resource-group <resource-group> --name <cluster-name>
   ```

2. **Verify cluster access**:
   ```bash
   kubectl get nodes
   kubectl get namespaces
   ```

3. **Deploy Profisee** (if not done automatically):
   ```bash
   helm repo add profisee https://profisee.github.io/kubernetes
   helm repo update
   helm install profisee profisee/profisee-platform --namespace profisee --create-namespace
   ```

4. **Access your deployment**:
   - Check the deployment outputs for URLs and connection information
   - Use the Azure Portal link provided to monitor resources

## Troubleshooting

### Common Issues

1. **Terraform validation errors**:
   - Ensure all required variables are set in `terraform.tfvars`
   - Check that resource names are globally unique (SQL Server, Storage Account)

2. **Authentication issues**:
   - Verify Azure CLI authentication: `az account show`
   - Ensure you have proper permissions on the subscription

3. **Resource naming conflicts**:
   - SQL Server and Storage Account names must be globally unique
   - Use a naming convention with your organization prefix

4. **Quota limitations**:
   - Check Azure subscription quotas for VM cores
   - Consider reducing node counts if hitting limits

5. **Key Vault access issues**:
   - Ensure Key Vault name is globally unique
   - Verify Managed Identity permissions on Key Vault
   - Check that CSI Secret Store Driver is properly installed in AKS

### Getting Help

- Check Terraform output for detailed error messages
- Use `terraform plan` to preview changes before applying
- Review Azure Activity Log in the portal for resource-level errors
- Check the deployment script logs for detailed error information


## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

**⚠️ Warning**: This will permanently delete all resources created by Terraform. Ensure you have backups of any important data.

## File Structure

```
Azure-Terraform/
├── main.tf                           # Main Terraform configuration with Key Vault support
├── variables.tf                      # Variable definitions including Key Vault options
├── outputs.tf                        # Output definitions with Key Vault information
├── versions.tf                       # Provider version constraints
├── terraform.tfvars                  # Variable values (customize this)
├── terraform.tfstate                 # Terraform state file (auto-generated)
├── terraform.tfstate.backup          # State backup (auto-generated)
├── .terraform.lock.hcl               # Provider lock file (auto-generated)
├── deploy.bat                        # Windows deployment script
├── deploy.sh                         # Linux/Mac deployment script
├── QUICK-START.md                    # Quick deployment guide
├── DEPLOYMENT-GUIDE.md               # Detailed deployment instructions
├── MIGRATION-NOTES.md                # Notes for migrating from ARM templates
└── README.md                         # This comprehensive documentation

# Legacy ARM Template Files (for reference):
├── azuredeploy.json                  # Original ARM template
├── azuredeploy.parameters.json       # ARM template parameters
├── deployprofisee.sh                 # Legacy deployment script
├── Settings.yaml                     # Legacy configuration
└── nginxSettings.yaml                # NGINX configuration
```

## Support

For assistance:

- **Terraform Issues**: Check Terraform documentation and this README
- **Profisee Platform**: Contact [Profisee Support](https://support.profisee.com)
- **Azure Services**: Refer to Azure documentation
- **Configuration Questions**: Review the variable descriptions in `variables.tf`

## Contributing

When making changes:

1. Follow HashiCorp's Terraform style guide
2. Run `terraform fmt` to format code  
3. Run `terraform validate` to check syntax
4. Test in development environment first
5. Update documentation as needed
