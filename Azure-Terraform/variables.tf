# Input variables for Profisee Platform deployment

variable "resource_group_name" {
  description = "Name of the resource group where resources will be deployed"
  type        = string
}

variable "profisee_version" {
  description = "Profisee platform version"
  type        = string
  default     = "profiseeplatform:2025r1.0"
}

variable "profisee_admin_user_account" {
  description = "Profisee admin user account"
  type        = string
}

variable "profisee_license" {
  description = "Profisee license data"
  type        = string
  sensitive   = true
}

variable "profisee_web_app_name" {
  description = "Profisee web application name"
  type        = string
}

variable "active_directory_create_app" {
  description = "Whether to create new Active Directory application"
  type        = string
  default     = "Yes"
  validation {
    condition     = contains(["Yes", "No"], var.active_directory_create_app)
    error_message = "Must be 'Yes' or 'No'."
  }
}

variable "active_directory_client_id" {
  description = "Existing Active Directory client ID"
  type        = string
  default     = ""
}

variable "active_directory_client_secret" {
  description = "Existing Active Directory client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "use_purview" {
  description = "Whether to use Azure Purview"
  type        = string
  default     = "No"
  validation {
    condition     = contains(["Yes", "No"], var.use_purview)
    error_message = "Must be 'Yes' or 'No'."
  }
}

variable "purview_url" {
  description = "Azure Purview URL"
  type        = string
  default     = ""
}

variable "purview_collection_friendly_name" {
  description = "Azure Purview collection friendly name"
  type        = string
  default     = ""
}

variable "purview_client_id" {
  description = "Azure Purview client ID"
  type        = string
  default     = ""
}

variable "purview_client_secret" {
  description = "Azure Purview client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "purview_account_resource_group" {
  description = "Azure Purview account resource group"
  type        = string
  default     = ""
}

variable "managed_identity_name" {
  description = "Managed identity configuration"
  type = object({
    name = optional(string, "")
  })
  default = {}
}

variable "kubernetes_infrastructure_resource_group_name" {
  description = "Kubernetes infrastructure resource group name"
  type        = string
  default     = ""
}

variable "windows_node_version" {
  description = "Windows node version"
  type        = string
  default     = ""
}

variable "kubernetes_cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
}

variable "kubernetes_linux_node_size" {
  description = "Kubernetes Linux node VM size"
  type        = string
  default     = "Standard_D4as_v5"
}

variable "kubernetes_linux_node_count" {
  description = "Kubernetes Linux node count"
  type        = number
  default     = 2
  validation {
    condition     = var.kubernetes_linux_node_count >= 1 && var.kubernetes_linux_node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

variable "kubernetes_windows_node_size" {
  description = "Kubernetes Windows node VM size"
  type        = string
  default     = "Standard_D8as_v5"
}

variable "kubernetes_windows_node_count" {
  description = "Kubernetes Windows node count"
  type        = number
  default     = 1
  validation {
    condition     = var.kubernetes_windows_node_count >= 0 && var.kubernetes_windows_node_count <= 100
    error_message = "Node count must be between 0 and 100."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = ""
}

variable "kubernetes_vnet_name" {
  description = "Existing virtual network name for Kubernetes"
  type        = string
  default     = ""
}

variable "kubernetes_vnet_resource_group" {
  description = "Resource group of existing virtual network"
  type        = string
  default     = ""
}

variable "kubernetes_subnet_name" {
  description = "Existing subnet name for Kubernetes"
  type        = string
  default     = ""
}

variable "kubernetes_service_cidr" {
  description = "Kubernetes service CIDR"
  type        = string
  default     = ""
}

variable "kubernetes_dns_service_ip" {
  description = "Kubernetes DNS service IP"
  type        = string
  default     = ""
}

variable "kubernetes_docker_bridge_cidr" {
  description = "Kubernetes Docker bridge CIDR"
  type        = string
  default     = ""
}

variable "authentication_type" {
  description = "Authentication type for AKS cluster"
  type        = string
  default     = "AAD"
  validation {
    condition     = contains(["AAD", "ServicePrincipal"], var.authentication_type)
    error_message = "Must be 'AAD' or 'ServicePrincipal'."
  }
}

variable "infra_admin_account" {
  description = "Infrastructure admin account name"
  type        = string
  default     = ""
}

variable "infra_admin_password" {
  description = "Infrastructure admin password for Windows nodes"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sql_server_create_new" {
  description = "Whether to create new SQL Server"
  type        = string
  default     = "Yes"
  validation {
    condition     = contains(["Yes", "No"], var.sql_server_create_new)
    error_message = "Must be 'Yes' or 'No'."
  }
}

variable "sql_server_name" {
  description = "SQL Server name"
  type        = string
}

variable "sql_server_user" {
  description = "SQL Server admin username"
  type        = string
  default     = "sqladmin"
}

variable "sql_server_password" {
  description = "SQL Server admin password"
  type        = string
  sensitive   = true
}

variable "sql_server_database_name" {
  description = "SQL Server database name"
  type        = string
  default     = "Profisee"
}

variable "storage_account_create_new" {
  description = "Whether to create new storage account"
  type        = string
  default     = "Yes"
  validation {
    condition     = contains(["Yes", "No"], var.storage_account_create_new)
    error_message = "Must be 'Yes' or 'No'."
  }
}

variable "storage_account_name" {
  description = "Storage account name"
  type        = string
}

variable "storage_account_type" {
  description = "Storage account type"
  type        = string
  default     = "Standard_LRS"
  validation {
    condition = contains([
      "Standard_LRS", "Standard_GRS", "Standard_RAGRS", "Standard_ZRS",
      "Premium_LRS", "Premium_ZRS", "Standard_GZRS", "Standard_RAGZRS"
    ], var.storage_account_type)
    error_message = "Must be a valid Azure storage account type."
  }
}

variable "storage_account_access_key" {
  description = "Existing storage account access key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "storage_account_file_share_name" {
  description = "Storage account file share name"
  type        = string
}

variable "dns_update" {
  description = "Whether to update DNS"
  type        = string
  default     = "No"
  validation {
    condition     = contains(["Yes", "No"], var.dns_update)
    error_message = "Must be 'Yes' or 'No'."
  }
}

variable "dns_host_name" {
  description = "DNS host name"
  type        = string
  default     = ""
}

variable "dns_domain_name" {
  description = "DNS domain name"
  type        = string
  default     = ""
}

variable "dns_domain_resource_group" {
  description = "DNS domain resource group"
  type        = string
  default     = ""
}

variable "https_configure" {
  description = "Whether to configure HTTPS"
  type        = string
  default     = "No"
  validation {
    condition     = contains(["Yes", "No"], var.https_configure)
    error_message = "Must be 'Yes' or 'No'."
  }
}

variable "https_certificate" {
  description = "HTTPS certificate content"
  type        = string
  default     = ""
  sensitive   = true
}

variable "https_certificate_private_key" {
  description = "HTTPS certificate private key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "use_lets_encrypt" {
  description = "Whether to use Let's Encrypt for SSL certificates"
  type        = string
  default     = "No"
  validation {
    condition     = contains(["Yes", "No"], var.use_lets_encrypt)
    error_message = "Must be 'Yes' or 'No'."
  }
}

variable "use_key_vault" {
  description = "Whether to use Azure Key Vault"
  type        = string
  default     = "No"
  validation {
    condition     = contains(["Yes", "No"], var.use_key_vault)
    error_message = "Must be 'Yes' or 'No'."
  }
}

variable "key_vault" {
  description = "Azure Key Vault resource ID"
  type        = string
  default     = ""
}

variable "acr_user" {
  description = "Azure Container Registry username"
  type        = string
  default     = ""
}

variable "acr_user_password" {
  description = "Azure Container Registry password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "new_guid" {
  description = "New GUID for deployment"
  type        = string
  default     = ""
}
