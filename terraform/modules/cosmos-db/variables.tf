# modules/cosmos-db/variables.tf - Variable definitions for Cosmos DB module

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region to deploy the Cosmos DB"
  type        = string
}

variable "cosmos_account_name" {
  description = "Name of the Cosmos DB account"
  type        = string
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "restaurant-db"
}

variable "container_name" {
  description = "Name of the container"
  type        = string
  default     = "restaurants"
}

variable "partition_key_path" {
  description = "Partition key path for the container"
  type        = string
  default     = "/style"
}

variable "key_vault_id" {
  description = "ID of the Key Vault to store secrets in (optional)"
  type        = string
  default     = null
}

variable "enable_serverless" {
  description = "Whether to enable serverless capacity mode"
  type        = bool
  default     = true
}

variable "consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  validation {
    condition     = contains(["Eventual", "Session", "BoundedStaleness", "Strong", "ConsistentPrefix"], var.consistency_level)
    error_message = "Consistency level must be one of: Eventual, Session, BoundedStaleness, Strong, or ConsistentPrefix."
  }
}

variable "public_network_access_enabled" {
  description = "Whether to enable public network access"
  type        = bool
  default     = true
}

variable "indexing_policy" {
  description = "Custom indexing policy for the container"
  type = object({
    indexing_mode  = string
    included_paths = list(string)
    excluded_paths = list(string)
  })
  default = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}