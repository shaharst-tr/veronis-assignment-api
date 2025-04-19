# Variables for the Key Vault module

variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region to deploy the Key Vault"
  type        = string
}

variable "network_acls_default_action" {
  description = "Default action for Key Vault network ACLs"
  type        = string
  default     = "Allow"
  
  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "Default action must be either 'Allow' or 'Deny'."
  }
}

variable "network_acls_bypass" {
  description = "Bypass setting for Key Vault network ACLs"
  type        = string
  default     = "AzureServices"
  
  validation {
    condition     = contains(["None", "AzureServices"], var.network_acls_bypass)
    error_message = "Bypass must be either 'None' or 'AzureServices'."
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges to allow access to the Key Vault"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the Key Vault"
  type        = map(string)
  default     = {}
}