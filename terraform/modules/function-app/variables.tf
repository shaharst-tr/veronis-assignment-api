# modules/function-app/variables.tf - Variable definitions for Function App module

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region to deploy the Function App"
  type        = string
}

variable "function_app_name" {
  description = "Name of the Function App"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the Storage Account for the Function App"
  type        = string
}

variable "app_insights_name" {
  description = "Name of the Application Insights resource"
  type        = string
}

variable "app_service_plan_name" {
  description = "Name of the App Service Plan"
  type        = string
}

variable "app_service_plan_sku" {
  description = "SKU for the App Service Plan (Y1 for consumption plan)"
  type        = string
  default     = "B1" # Consumption plan by default
}

variable "python_version" {
  description = "Python version for the Function App"
  type        = string
  default     = "3.9"
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
}

variable "cors_allowed_origins" {
  description = "List of origins to allow CORS for"
  type        = list(string)
  default     = ["*"]
}

variable "cors_support_credentials" {
  description = "Are credentials supported for CORS?"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Path for health check endpoint (if required)"
  type        = string
  default     = null
}

variable "identity_type" {
  description = "Type of identity to use for the Function App (SystemAssigned, UserAssigned, or 'SystemAssigned, UserAssigned')"
  type        = string
  default     = "SystemAssigned"
  
  validation {
    condition     = contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity_type)
    error_message = "The identity type must be 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'."
  }
}

variable "identity_ids" {
  description = "List of user-assigned identity IDs to be assigned to the Function App"
  type        = list(string)
  default     = []
}

variable "additional_app_settings" {
  description = "Additional app settings for the Function App"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}