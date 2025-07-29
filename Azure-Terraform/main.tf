# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Data source for resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Data source for existing VNet if specified
data "azurerm_virtual_network" "existing" {
  count               = var.kubernetes_vnet_name != "" ? 1 : 0
  name                = var.kubernetes_vnet_name
  resource_group_name = var.kubernetes_vnet_resource_group != "" ? var.kubernetes_vnet_resource_group : var.resource_group_name
}

# Data source for existing subnet if specified
data "azurerm_subnet" "existing" {
  count                = var.kubernetes_vnet_name != "" && var.kubernetes_subnet_name != "" ? 1 : 0
  name                 = var.kubernetes_subnet_name
  virtual_network_name = var.kubernetes_vnet_name
  resource_group_name  = var.kubernetes_vnet_resource_group != "" ? var.kubernetes_vnet_resource_group : var.resource_group_name
}

# Create Azure SQL Server (if new)
resource "azurerm_mssql_server" "profisee" {
  count                        = var.sql_server_create_new == "Yes" ? 1 : 0
  name                         = lower(var.sql_server_name)
  resource_group_name          = data.azurerm_resource_group.main.name
  location                     = data.azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_server_user
  administrator_login_password = var.sql_server_password
  minimum_tls_version          = "1.2"

  azuread_administrator {
    login_username = var.profisee_admin_user_account
    object_id      = data.azurerm_client_config.current.object_id
  }

  tags = {
    displayName = "SQLServer"
    Environment = "Profisee"
  }
}

# Create Azure SQL Database
resource "azurerm_mssql_database" "profisee" {
  count          = var.sql_server_create_new == "Yes" ? 1 : 0
  name           = var.sql_server_database_name
  server_id      = azurerm_mssql_server.profisee[0].id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 250
  sku_name       = "S2"
  zone_redundant = false

  tags = {
    displayName = "SQLDatabase"
    Environment = "Profisee"
  }
}

# Create SQL Server firewall rule to allow Azure services
resource "azurerm_mssql_firewall_rule" "allow_azure" {
  count            = var.sql_server_create_new == "Yes" ? 1 : 0
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.profisee[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create Storage Account (if new)
resource "azurerm_storage_account" "profisee" {
  count                      = var.storage_account_create_new == "Yes" ? 1 : 0
  name                       = lower(var.storage_account_name)
  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = data.azurerm_resource_group.main.location
  account_tier               = split("_", var.storage_account_type)[0]
  account_replication_type   = split("_", var.storage_account_type)[1]
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  allow_nested_items_to_be_public = false

  tags = {
    displayName = "StorageAccount"
    Environment = "Profisee"
  }
}

# Create File Share
resource "azurerm_storage_share" "profisee" {
  count                = var.storage_account_create_new == "Yes" ? 1 : 0
  name                 = var.storage_account_file_share_name
  storage_account_name = azurerm_storage_account.profisee[0].name
  quota                = 50
}

# Generate a random password for Windows admin if not provided
resource "random_password" "windows_admin" {
  length  = 16
  special = true
}

# Create Azure Kubernetes Service
resource "azurerm_kubernetes_cluster" "profisee" {
  name                = var.kubernetes_cluster_name
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = "${var.kubernetes_cluster_name}-dns"
  kubernetes_version  = var.kubernetes_version != "" ? var.kubernetes_version : null

  # Node resource group
  node_resource_group = var.kubernetes_infrastructure_resource_group_name != "" ? var.kubernetes_infrastructure_resource_group_name : "${data.azurerm_resource_group.main.name}-nodes"

  default_node_pool {
    name       = "linuxpool"
    node_count = var.kubernetes_linux_node_count
    vm_size    = var.kubernetes_linux_node_size
    type       = "VirtualMachineScaleSets"

    # Use existing subnet if specified
    vnet_subnet_id = var.kubernetes_vnet_name != "" && var.kubernetes_subnet_name != "" ? data.azurerm_subnet.existing[0].id : null
  }

  # Windows node pool configuration
  windows_profile {
    admin_username = var.infra_admin_account != "" ? var.infra_admin_account : "azureuser"
    admin_password = var.infra_admin_password != "" ? var.infra_admin_password : random_password.windows_admin.result
  }

  # Network configuration
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = var.kubernetes_service_cidr != "" ? var.kubernetes_service_cidr : "10.0.0.0/16"
    dns_service_ip = var.kubernetes_dns_service_ip != "" ? var.kubernetes_dns_service_ip : "10.0.0.10"
  }

  # Identity configuration - using SystemAssigned for AKS
  identity {
    type = "SystemAssigned"
  }

  # Azure AD integration
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.authentication_type == "AAD" ? [1] : []
    content {
      azure_rbac_enabled     = true
      admin_group_object_ids = []
    }
  }

  tags = {
    displayName = "AKSCluster"
    Environment = "Profisee"
  }
}

# Create Windows node pool
resource "azurerm_kubernetes_cluster_node_pool" "windows" {
  name                  = "winpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.profisee.id
  vm_size               = var.kubernetes_windows_node_size
  node_count            = var.kubernetes_windows_node_count
  os_type               = "Windows"

  # Use existing subnet if specified
  vnet_subnet_id = var.kubernetes_vnet_name != "" && var.kubernetes_subnet_name != "" ? data.azurerm_subnet.existing[0].id : null

  tags = {
    displayName = "WindowsNodePool"
    Environment = "Profisee"
  }
}

# User-assigned managed identity for Profisee workloads
resource "azurerm_user_assigned_identity" "profisee" {
  count               = length(var.managed_identity_name) > 0 ? 1 : 0
  name                = var.managed_identity_name.name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location

  tags = {
    displayName = "ProfiseeManagedIdentity"
    Environment = "Profisee"
  }
}

# Role assignment for AKS to pull from ACR (if using container registry)
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = var.acr_user != "" ? 1 : 0
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.profisee.kubelet_identity[0].object_id
}

# Create Azure AD Application (if required)
resource "azuread_application" "profisee" {
  count        = var.active_directory_create_app == "Yes" && var.active_directory_client_id == "" ? 1 : 0
  display_name = "${var.profisee_web_app_name}-app"

  web {
    homepage_url  = "https://${var.dns_host_name}.${var.dns_domain_name}"
    redirect_uris = ["https://${var.dns_host_name}.${var.dns_domain_name}/profisee/auth/signin-oidc"]

    implicit_grant {
      access_token_issuance_enabled = true
      id_token_issuance_enabled     = true
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

# Create service principal for the AD application
resource "azuread_service_principal" "profisee" {
  count     = var.active_directory_create_app == "Yes" && var.active_directory_client_id == "" ? 1 : 0
  client_id = azuread_application.profisee[0].client_id
}

# Create client secret for the AD application
resource "azuread_application_password" "profisee" {
  count          = var.active_directory_create_app == "Yes" && var.active_directory_client_id == "" ? 1 : 0
  application_id = azuread_application.profisee[0].id
  display_name   = "Profisee Client Secret"
}
