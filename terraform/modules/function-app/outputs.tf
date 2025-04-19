# modules/function-app/outputs.tf - Output values from the Function App module

output "function_app_id" {
  description = "The ID of the Function App"
  value       = azurerm_linux_function_app.function_app.id
}

output "function_app_name" {
  description = "The name of the Function App"
  value       = azurerm_linux_function_app.function_app.name
}

output "function_app_hostname" {
  description = "The default hostname of the Function App"
  value       = azurerm_linux_function_app.function_app.default_hostname
}

output "function_app_principal_id" {
  description = "The Principal ID of the Function App's managed identity"
  value       = azurerm_linux_function_app.function_app.identity[0].principal_id
}

output "storage_account_name" {
  description = "The name of the Storage Account"
  value       = azurerm_storage_account.func_storage.name
}

output "app_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.func_insights.instrumentation_key
  sensitive   = true
}

output "app_insights_connection_string" {
  description = "The connection string for Application Insights"
  value       = azurerm_application_insights.func_insights.connection_string
  sensitive   = true
}
output "storage_account_connection_string" {
  description = "The connection string for the Storage Account"
  value       = azurerm_storage_account.func_storage.primary_connection_string
  sensitive   = true
}