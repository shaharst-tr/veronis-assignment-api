# Outputs for the networking module

output "app_gateway_id" {
  description = "The ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "app_gateway_name" {
  description = "The name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "app_gateway_public_ip" {
  description = "The public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "app_gateway_fqdn" {
  description = "The FQDN of the Application Gateway public IP"
  value       = azurerm_public_ip.appgw.fqdn
}

output "vnet_id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "function_subnet_id" {
  description = "The ID of the subnet used for function app integration"
  value       = azurerm_subnet.function_integration.id
}

output "appgw_subnet_id" {
  description = "The ID of the subnet used for Application Gateway"
  value       = azurerm_subnet.appgw.id
}