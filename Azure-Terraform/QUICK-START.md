# Profisee Platform - Simplified Deployment

## Prerequisites
- Terraform: `winget install HashiCorp.Terraform`
- Azure CLI: `az login`

## 3-Step Deployment

### 1. Configure
```bash
copy sample.tfvars terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Deploy
**Option A - Interactive:**
```bash
terraform init
terraform plan
terraform apply
```

**Option B - One-click:**
- Windows: Double-click `deploy.bat`
- Linux/WSL: `./deploy.sh`

### 3. Access
```bash
# Get deployment info
terraform output deployment_summary

# Get next steps
terraform output next_steps
```

## Essential Configuration
Only these fields are required in `terraform.tfvars`:
```hcl
resource_group_name            = "profisee-rg"
profisee_admin_user_account    = "admin@company.com"
profisee_license              = "your-license-key"
profisee_web_app_name         = "profisee-app"
sql_server_name               = "unique-sql-server-name"
sql_server_password           = "SecurePassword123!"
storage_account_name          = "uniquestorageaccount"
storage_account_file_share_name = "profisee-fileshare"
```

## Post-Deployment
Run the commands from `terraform output next_steps`:
1. Get AKS credentials
2. Install Profisee via Helm
3. Access Azure Portal

That's it! 🚀
