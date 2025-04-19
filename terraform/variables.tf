# variables.tf - Variables for the restaurant API project

variable "subscription_id" {
  description = "The Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "The Azure tenant ID"
  type        = string
}

variable "project_name" {
  description = "The name of the project, used as a prefix for resources"
  type        = string
  default     = "restaurant-api"
}

variable "environment" {
  description = "The environment (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "The Azure location where resources should be created"
  type        = string
  default     = "northeurope"
}

variable "cosmos_db_name" {
  description = "The name of the Cosmos DB database"
  type        = string
  default     = "RestaurantDatabase"
}

variable "cosmos_container_name" {
  description = "The name of the Cosmos DB container"
  type        = string
  default     = "Restaurants"
}

variable "key_vault_network_default_action" {
  description = "Default action for Key Vault network ACLs"
  type        = string
  default     = "Allow"
}

variable "key_vault_network_bypass" {
  description = "Network bypass for Key Vault"
  type        = string
  default     = "AzureServices"
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges to allow access to Key Vault"
  type        = list(string)
  default     = []
}

variable "log_analytics_sku" {
  description = "The SKU of the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_retention_days" {
  description = "The number of days to retain logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}