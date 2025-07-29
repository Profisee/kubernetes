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
   ```

3. **Deploy with Terraform**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

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
  - `use_key_vault`: Enable Azure Key Vault integration
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
- **Key Vault Integration**: Optional integration for secrets management
- **Least Privilege**: Role assignments follow principle of least privilege

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
   - Ensure all required variables are set in `terraform.tfvars.json`
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

### Getting Help

- Check Terraform output for detailed error messages
- Use `terraform plan` to preview changes before applying
- Review Azure Activity Log in the portal for resource-level errors
- Check the deployment script logs for detailed error information

## Migration from ARM Template

This Terraform configuration replaces the ARM template deployment with these improvements:

✅ **Version Control**: Infrastructure code can be versioned and tracked  
✅ **Repeatability**: Consistent deployments across environments  
✅ **State Management**: Terraform tracks resource state for updates  
✅ **Dependency Management**: Automatic resource dependency resolution  
✅ **Validation**: Built-in validation for configuration values  
✅ **Preview Changes**: See what will be changed before deployment  
✅ **Modularity**: Easier to customize and extend  

### Key Differences from ARM:

- Uses `.tf` files instead of `.json` ARM templates
- Configuration in `terraform.tfvars.json` instead of parameters file
- Deployment via `terraform apply` instead of `az deployment`
- State file tracking (stored locally or in remote backend)
- More granular resource management and updates

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

**⚠️ Warning**: This will permanently delete all resources created by Terraform. Ensure you have backups of any important data.

## File Structure

```
Azure-Terraform/
├── main.tf                           # Main Terraform configuration
├── variables.tf                      # Variable definitions  
├── outputs.tf                        # Output definitions
├── versions.tf                       # Provider version constraints
├── terraform.tfvars                  # Variable values (customize this)
├── sample.tfvars                     # Sample configuration with examples
├── QUICK-START.md                   # Quick deployment guide
└── README-terraform.md              # This documentation
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
