# outputs.tf - Outputs for the restaurant API project

# Function App outputs
output "function_app_url" {
  description = "The default function app URL"
  value       = module.function_app.function_app_hostname
}

output "function_app_name" {
  description = "The name of the function app"
  value       = local.names.function_app
}

# Cosmos DB outputs
output "cosmos_db_endpoint" {
  description = "The endpoint of the Cosmos DB account"
  value       = module.cosmos_db.cosmos_db_endpoint
}

output "cosmos_db_name" {
  description = "The name of the Cosmos DB account"
  value       = module.cosmos_db.cosmos_db_name
}

# Key Vault outputs
output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = module.key_vault.key_vault_uri
}

# Storage outputs
output "storage_account_name" {
  description = "The name of the storage account"
  value       = module.function_app.storage_account_name
}

# Application Gateway outputs
output "app_gateway_public_ip" {
  description = "The public IP address of the Application Gateway"
  value       = module.networking.app_gateway_public_ip
}

output "app_gateway_fqdn" {
  description = "The FQDN of the Application Gateway"
  value       = module.networking.app_gateway_fqdn
}

# API endpoints through Application Gateway
output "recommendation_api_url" {
  description = "The URL for restaurant recommendations"
  value       = "https://${module.networking.app_gateway_fqdn}/api/restaurant-recommend"
}

output "admin_api_url" {
  description = "The URL for admin operations"
  value       = "https://${module.networking.app_gateway_fqdn}/api/restaurants/admin"
}

output "health_check_url" {
  description = "The URL for health checks"
  value       = "https://${module.networking.app_gateway_fqdn}/api/health"
}