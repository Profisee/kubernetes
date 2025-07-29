# Output values for Profisee Platform deployment

output "resource_group_name" {
  description = "Name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = data.azurerm_resource_group.main.location
}

output "kubernetes_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.profisee.name
}

output "kubernetes_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.profisee.id
}

output "kubernetes_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.profisee.fqdn
}

output "kubernetes_kube_config" {
  description = "Kube config for the AKS cluster"
  value       = azurerm_kubernetes_cluster.profisee.kube_config_raw
  sensitive   = true
}

output "kubernetes_client_certificate" {
  description = "Client certificate for AKS cluster"
  value       = azurerm_kubernetes_cluster.profisee.kube_config[0].client_certificate
  sensitive   = true
}

output "kubernetes_client_key" {
  description = "Client key for AKS cluster"
  value       = azurerm_kubernetes_cluster.profisee.kube_config[0].client_key
  sensitive   = true
}

output "kubernetes_cluster_ca_certificate" {
  description = "Cluster CA certificate for AKS cluster"
  value       = azurerm_kubernetes_cluster.profisee.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "kubernetes_host" {
  description = "Host for AKS cluster"
  value       = azurerm_kubernetes_cluster.profisee.kube_config[0].host
  sensitive   = true
}

output "sql_server_name" {
  description = "Name of the SQL Server"
  value       = var.sql_server_create_new == "Yes" ? azurerm_mssql_server.profisee[0].name : var.sql_server_name
}

output "sql_server_fqdn" {
  description = "FQDN of the SQL Server"
  value       = var.sql_server_create_new == "Yes" ? azurerm_mssql_server.profisee[0].fully_qualified_domain_name : "${var.sql_server_name}.database.windows.net"
}

output "sql_database_name" {
  description = "Name of the SQL Database"
  value       = var.sql_server_database_name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = var.storage_account_create_new == "Yes" ? azurerm_storage_account.profisee[0].name : var.storage_account_name
}

output "storage_account_primary_access_key" {
  description = "Primary access key of the storage account"
  value       = var.storage_account_create_new == "Yes" ? azurerm_storage_account.profisee[0].primary_access_key : var.storage_account_access_key
  sensitive   = true
}

output "storage_account_file_share_name" {
  description = "Name of the file share"
  value       = var.storage_account_file_share_name
}

output "managed_identity_id" {
  description = "ID of the user-assigned managed identity"
  value       = length(var.managed_identity_name) > 0 && var.managed_identity_name.name != "" ? azurerm_user_assigned_identity.profisee[0].id : null
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = length(var.managed_identity_name) > 0 && var.managed_identity_name.name != "" ? azurerm_user_assigned_identity.profisee[0].principal_id : null
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = length(var.managed_identity_name) > 0 && var.managed_identity_name.name != "" ? azurerm_user_assigned_identity.profisee[0].client_id : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.profisee.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.profisee.name
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.profisee.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.profisee.primary_shared_key
  sensitive   = true
}

output "azure_ad_application_id" {
  description = "Azure AD Application ID"
  value       = var.active_directory_create_app == "Yes" && var.active_directory_client_id == "" ? azuread_application.profisee[0].client_id : var.active_directory_client_id
}

output "azure_ad_client_secret" {
  description = "Azure AD Client Secret"
  value       = var.active_directory_create_app == "Yes" && var.active_directory_client_id == "" ? azuread_application_password.profisee[0].value : var.active_directory_client_secret
  sensitive   = true
}

output "azure_ad_tenant_id" {
  description = "Azure AD Tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group         = data.azurerm_resource_group.main.name
    location              = data.azurerm_resource_group.main.location
    aks_cluster           = azurerm_kubernetes_cluster.profisee.name
    sql_server            = var.sql_server_create_new == "Yes" ? azurerm_mssql_server.profisee[0].fully_qualified_domain_name : "${var.sql_server_name}.database.windows.net"
    storage_account       = var.storage_account_create_new == "Yes" ? azurerm_storage_account.profisee[0].name : var.storage_account_name
    log_analytics_workspace = azurerm_log_analytics_workspace.profisee.name
    subscription_id       = data.azurerm_client_config.current.subscription_id
    tenant_id            = data.azurerm_client_config.current.tenant_id
  }
}

# Commands for post-deployment
output "next_steps" {
  description = "Commands to run after deployment"
  value = {
    get_aks_credentials = "az aks get-credentials --resource-group ${data.azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.profisee.name}"
    add_helm_repo       = "helm repo add profisee https://profisee.github.io/kubernetes"
    install_profisee    = "helm install profisee profisee/profisee-platform --namespace profisee --create-namespace"
    azure_portal_url    = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${data.azurerm_resource_group.main.name}"
    log_analytics_url   = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.profisee.id}"
  }
}

# Monitoring and Logging Information
output "monitoring_info" {
  description = "Information about monitoring and logging setup"
  value = {
    log_analytics_workspace = azurerm_log_analytics_workspace.profisee.name
    aks_monitoring_enabled  = "Azure Monitor for containers is enabled"
    sql_diagnostics_enabled = var.sql_server_create_new == "Yes" ? "SQL Server and Database diagnostics are enabled" : "N/A"
    storage_diagnostics_enabled = var.storage_account_create_new == "Yes" ? "Storage Account diagnostics are enabled" : "N/A"
    retention_days = azurerm_log_analytics_workspace.profisee.retention_in_days
    workspace_id = azurerm_log_analytics_workspace.profisee.workspace_id
  }
}

# Outputs for deployment script variables
output "deployment_variables" {
  description = "Variables needed for Profisee deployment script"
  value = {
    PROFISEEVERSION     = var.profisee_version
    ADMINACCOUNTNAME    = var.profisee_admin_user_account
    LICENSEDATA         = var.profisee_license
    WEBAPPNAME          = var.profisee_web_app_name
    ACRUSER             = var.acr_user
    ACRUSERPASSWORD     = var.acr_user_password
    UPDATEAAD           = var.active_directory_create_app
    CLIENTID            = var.active_directory_create_app == "Yes" && var.active_directory_client_id == "" ? azuread_application.profisee[0].client_id : var.active_directory_client_id
    CLIENTSECRET        = var.active_directory_create_app == "Yes" && var.active_directory_client_id == "" ? azuread_application_password.profisee[0].value : var.active_directory_client_secret
    SQLFQDN             = var.sql_server_create_new == "Yes" ? azurerm_mssql_server.profisee[0].fully_qualified_domain_name : "${var.sql_server_name}.database.windows.net"
    SQLNAME             = var.sql_server_database_name
    SQLUSER             = var.sql_server_user
    SQLPASSWORD         = var.sql_server_password
    STORAGEACCOUNTNAME  = var.storage_account_create_new == "Yes" ? azurerm_storage_account.profisee[0].name : var.storage_account_name
    STORAGEACCOUNTKEY   = var.storage_account_create_new == "Yes" ? azurerm_storage_account.profisee[0].primary_access_key : var.storage_account_access_key
    FILESHARE           = var.storage_account_file_share_name
    DNSHOSTNAME         = var.dns_host_name
    DNSDOMAINNAME       = var.dns_domain_name
    HTTPSCONFIGURE      = var.https_configure
    HTTPSCERTIFICATE    = var.https_certificate
    HTTPSCERTIFICATEKEY = var.https_certificate_private_key
    USELETSENCRYPT      = var.use_lets_encrypt
    USEKEYVAULT         = var.use_key_vault
    KEYVAULT            = var.key_vault
    USEPURVIEW          = var.use_purview
    PURVIEWURL          = var.purview_url
    PURVIEWCOLLECTIONID = var.purview_collection_friendly_name
    PURVIEWCLIENTID     = var.purview_client_id
    PURVIEWCLIENTSECRET = var.purview_client_secret
  }
  sensitive = true
}
