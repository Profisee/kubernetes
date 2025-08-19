# Profisee Platform Deployment Guide - Terraform Migration

## Overview

This guide will help you migrate from the ARM template deployment to the new Terraform-based deployment for the Profisee Platform on Azure Kubernetes Service (AKS).

## What's New with Terraform

✅ **Infrastructure as Code**: Version-controlled, repeatable deployments  
✅ **Better State Management**: Terraform tracks all resource states  
✅ **Improved Dependency Handling**: Automatic resource dependency resolution  
✅ **Enhanced Validation**: Built-in configuration validation  
✅ **Preview Changes**: See exactly what will be changed before deployment  
✅ **Easier Updates**: Modify infrastructure through code changes  

## Prerequisites

1. **Install Required Tools**:
   ```powershell
   # Install Terraform
   winget install HashiCorp.Terraform
   
   # Install Azure CLI (if not already installed)
   winget install Microsoft.AzureCLI
   
   # Install kubectl (optional)
   winget install Kubernetes.kubectl
   
   # Install Helm (optional)
   winget install Helm.Helm
   ```

2. **Azure Authentication**:
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

3. **Azure Permissions**: Ensure your account has:
   - **Contributor** role on the subscription or resource group
   - **Application Administrator** role in Azure AD (if creating AD app)
   - **User Access Administrator** (for role assignments)

## Step-by-Step Deployment

### Step 1: Prepare Configuration

1. **Navigate to the Terraform directory**:
   ```bash
   cd Azure-Terraform
   ```

2. **Copy the sample configuration**:
   ```bash
   copy sample.tfvars terraform.tfvars
   ```

3. **Edit `terraform.tfvars`** with your specific values:
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

### Step 2: Deploy with Terraform

**Standard Terraform Workflow:**
```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply changes
terraform apply
```

**Alternative - Single Command:**
```bash
# Initialize and apply in one step
terraform init && terraform plan && terraform apply
```

### Step 3: Post-Deployment

1. **Get AKS credentials**:
   ```bash
   az aks get-credentials --resource-group <resource-group> --name <cluster-name>
   ```

2. **Verify cluster**:
   ```bash
   kubectl get nodes
   kubectl get namespaces
   ```

3. **Deploy Profisee** (if not done automatically):
   ```bash
   helm repo add profisee https://profisee.github.io/kubernetes
   helm install profisee profisee/profisee-platform --namespace profisee --create-namespace
   ```

## Configuration Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `resource_group_name` | Resource group name | `"profisee-rg"` |
| `profisee_admin_user_account` | Admin user email | `"admin@company.com"` |
| `profisee_license` | License key | `"license-key"` |
| `profisee_web_app_name` | App name | `"profisee-app"` |
| `sql_server_name` | SQL Server name (unique) | `"profisee-sql"` |
| `sql_server_password` | SQL password | `"SecurePass123!"` |
| `storage_account_name` | Storage name (unique) | `"profiseestorage"` |
| `storage_account_file_share_name` | File share name | `"profisee-share"` |

### Optional Customizations

- **Cluster Sizing**: Adjust node counts and VM sizes
- **Networking**: Use existing VNet/subnet
- **DNS**: Configure custom domain
- **HTTPS**: Enable SSL certificates
- **Key Vault**: Store secrets securely
- **Purview**: Enable data governance

## Comparison: ARM vs Terraform

| Feature | ARM Template | Terraform |
|---------|--------------|-----------|
| **Syntax** | JSON | HCL (Human-readable) |
| **State Management** | Azure-managed | Local/Remote state |
| **Planning** | Limited preview | Full plan preview |
| **Modularity** | Limited | Highly modular |
| **Version Control** | Basic | Advanced |
| **Error Handling** | Complex | Detailed |
| **Updates** | Replace entire stack | Incremental updates |

## Migration from ARM Template

If you're migrating from the existing ARM template:

1. **Backup existing deployment** information
2. **Review current configuration** in the ARM parameters file
3. **Map ARM parameters** to Terraform variables
4. **Test deployment** in a separate resource group first
5. **Plan migration strategy** (parallel deployment vs replacement)

### Parameter Mapping

| ARM Parameter | Terraform Variable |
|---------------|-------------------|
| `ProfiseeVersion` | `profisee_version` |
| `ProfiseeAdminUserAccount` | `profisee_admin_user_account` |
| `ProfiseeLicense` | `profisee_license` |
| `KubernetesClusterName` | `kubernetes_cluster_name` |
| `SQLServerName` | `sql_server_name` |
| `StorageAccountName` | `storage_account_name` |

## Troubleshooting

### Common Issues

1. **Resource Name Conflicts**:
   - SQL Server and Storage Account names must be globally unique
   - Use company/project prefixes

2. **Permission Errors**:
   - Verify Azure CLI authentication: `az account show`
   - Check subscription permissions

3. **Terraform State Issues**:
   - Use `terraform refresh` to sync state
   - Check `.terraform/` directory permissions

4. **Validation Errors**:
   - Run `terraform validate` to check syntax
   - Review variable types and constraints

### Getting Help

1. **Check Terraform output** for detailed error messages
2. **Review Azure Activity Log** in the portal
3. **Use Terraform debugging**:
   ```bash
   export TF_LOG=DEBUG
   terraform apply
   ```

## Best Practices

### Security
- Store sensitive values in Azure Key Vault
- Use managed identities where possible
- Enable RBAC on AKS cluster
- Regular security updates

### Operations
- Use remote state storage for team collaboration
- Tag all resources consistently
- Monitor resource costs
- Set up backup procedures

### Development
- Use separate environments (dev/staging/prod)
- Version control all configuration
- Test changes in development first
- Document custom configurations

## Support and Resources

- **Terraform Documentation**: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- **Azure Kubernetes Service**: https://docs.microsoft.com/en-us/azure/aks/
- **Profisee Support**: https://support.profisee.com
- **Helm Charts**: https://profisee.github.io/kubernetes

## Next Steps

After successful deployment:

1. Set up monitoring and alerting
2. Configure backup procedures
3. Implement CI/CD pipelines
4. Plan for disaster recovery
5. Train team on Terraform operations

---

**Need Help?** Contact your system administrator or Profisee support for assistance with the migration process.
