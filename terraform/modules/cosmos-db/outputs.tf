# modules/cosmos-db/outputs.tf - Output values from the Cosmos DB module

output "cosmos_db_id" {
  description = "The ID of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.db.id
}

output "cosmos_db_name" {
  description = "The name of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.db.name
}

output "cosmos_db_endpoint" {
  description = "The endpoint of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.db.endpoint
}

output "cosmos_db_primary_key" {
  description = "The primary key of the Cosmos DB account"
  value       = azurerm_cosmosdb_account.db.primary_key
  sensitive   = true
}

output "database_name" {
  description = "The name of the SQL database"
  value       = azurerm_cosmosdb_sql_database.db.name
}

output "container_name" {
  description = "The name of the SQL container"
  value       = azurerm_cosmosdb_sql_container.container.name
}

output "role_definitions_id" {
  description = "The ID to use for role definition references"
  value       = "${azurerm_cosmosdb_account.db.id}/sqlRoleDefinitions"
}