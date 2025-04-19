# Variables for the networking module

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
}

variable "location" {
  description = "The Azure location where resources should be created"
  type        = string
}

variable "function_app_hostname" {
  description = "The hostname of the function app"
  type        = string
}

variable "function_app_id" {
  description = "The ID of the function app"
  type        = string
}

variable "function_app_name" {
  description = "The name of the function app"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "waf_mode" {
  description = "The mode of the Web Application Firewall (WAF)"
  type        = string
  default     = "Detection"
  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be either 'Detection' or 'Prevention'."
  }
}

variable "vnet_address_space" {
  description = "The address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "function_subnet_prefix" {
  description = "The address prefix for the function app subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "key_vault_secret_id" {
  description = "The Secret ID of the certificate in Key Vault"
  type        = string
}

variable "appgw_identity_id" {
  description = "The ID of the user-assigned managed identity for Application Gateway"
  type        = string
}

variable "enable_http_to_https_redirect" {
  description = "Enable HTTP to HTTPS redirect"
  type        = bool
  default     = true
}