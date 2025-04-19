# Networking Module for Restaurant API
# Configures Azure Application Gateway with WAF and function app backend

# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.resource_group_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = lower(replace(replace(var.resource_group_name, "-rg", ""), "-", ""))

  tags = var.tags
}

# Virtual Network for Application Gateway
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.resource_group_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.vnet_address_space

  tags = var.tags
}

# Subnet for Application Gateway
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Subnet for Function App integration
resource "azurerm_subnet" "function_integration" {
  name                 = "snet-function"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.function_subnet_prefix
  
  delegation {
    name = "function-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.AzureCosmosDB"]
}

# Network Security Group for the function app subnet
resource "azurerm_network_security_group" "function" {
  name                = "nsg-function"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Allow traffic from Application Gateway to function app
resource "azurerm_network_security_rule" "allow_appgw" {
  name                        = "AllowAppGateway"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = azurerm_subnet.appgw.address_prefixes[0]
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function.name
}

# Associate NSG with function subnet
resource "azurerm_subnet_network_security_group_association" "function" {
  subnet_id                 = azurerm_subnet.function_integration.id
  network_security_group_id = azurerm_network_security_group.function.id
}

# Add VNet integration to function app
resource "azurerm_app_service_virtual_network_swift_connection" "function_vnet_integration" {
  app_service_id = var.function_app_id
  subnet_id      = azurerm_subnet.function_integration.id
}

# Application Gateway with WAF enabled
resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.resource_group_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  
  identity {
    type         = "UserAssigned"
    identity_ids = [var.appgw_identity_id]
  }
  
  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }
  
  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }
  
  # Frontend configuration
  frontend_port {
    name = "https-port"
    port = 443
  }

  frontend_port {
    name = "http-port"
    port = 80
  }
  
  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }
  
  # Backend configuration for restaurant recommendation API
  backend_address_pool {
    name = "restaurant-recommend-pool"
    fqdns = [var.function_app_hostname]
  }
  
  # Backend configuration for admin API
  backend_address_pool {
    name = "admin-pool"
    fqdns = [var.function_app_hostname]
  }

  # Backend configuration for health check
  backend_address_pool {
    name = "health-pool"
    fqdns = [var.function_app_hostname]
  }
  
  # Backend settings for restaurant recommendation API
  backend_http_settings {
    name                  = "restaurant-recommend-settings"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 60
    host_name             = var.function_app_hostname
    probe_name            = "health-probe"
    
    # Enable caching for recommendation API
    pick_host_name_from_backend_address = false
  }
  
  # Backend settings for admin API
  backend_http_settings {
    name                  = "admin-settings"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 180  # Longer timeout for admin operations
    host_name             = var.function_app_hostname
    probe_name            = "health-probe"
    
    # No caching for admin API
    pick_host_name_from_backend_address = false
  }

  # Backend settings for health check
  backend_http_settings {
    name                  = "health-settings"
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 30
    host_name             = var.function_app_hostname
    
    pick_host_name_from_backend_address = false
  }
  
  # Health probe
  probe {
    name                = "health-probe"
    protocol            = "Https"
    path                = "/api/health"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    host                = var.function_app_hostname
    match {
      status_code = ["200-399"]
    }
  }
  
  # HTTP listener (for redirect)
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  # HTTPS listener (single listener for all paths)
  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "https-port"
    protocol                       = "Https"
    ssl_certificate_name           = "appgw-ssl-cert"
  }

  # HTTP to HTTPS redirect rule
  request_routing_rule {
    name                       = "http-to-https-redirect"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    redirect_configuration_name = "http-to-https-redirect"
    priority                   = 10
  }

  # Main routing rule (uses URL path map)
  request_routing_rule {
    name                       = "main-rule"
    rule_type                  = "PathBasedRouting"
    http_listener_name         = "https-listener"
    url_path_map_name          = "api-path-map"
    priority                   = 20
  }

  # HTTP to HTTPS redirect configuration
  redirect_configuration {
    name                 = "http-to-https-redirect"
    redirect_type        = "Permanent"
    target_listener_name = "https-listener"
    include_path         = true
    include_query_string = true
  }

  # URL path map for all API paths
  url_path_map {
    name                               = "api-path-map"
    default_backend_address_pool_name  = "restaurant-recommend-pool"
    default_backend_http_settings_name = "restaurant-recommend-settings"
    
    # Restaurant recommendations path
    path_rule {
      name                       = "restaurant-recommend-path"
      paths                      = ["/api/restaurant-recommend*"]
      backend_address_pool_name  = "restaurant-recommend-pool"
      backend_http_settings_name = "restaurant-recommend-settings"
    }
    
    # Admin API path
    path_rule {
      name                       = "admin-path"
      paths                      = ["/api/restaurants/admin*"]
      backend_address_pool_name  = "admin-pool"
      backend_http_settings_name = "admin-settings"
    }
    
    # Health check path
    path_rule {
      name                       = "health-path"
      paths                      = ["/api/health"]
      backend_address_pool_name  = "health-pool"
      backend_http_settings_name = "health-settings"
    }
  }
  
  # SSL certificate for HTTPS
  ssl_certificate {
    name                = "appgw-ssl-cert"
    key_vault_secret_id = var.key_vault_secret_id
  }
  
  # WAF configuration
  waf_configuration {
    enabled                  = true
    firewall_mode            = var.waf_mode
    rule_set_type            = "OWASP"
    rule_set_version         = "3.2"
    file_upload_limit_mb     = 100
    request_body_check       = true
    max_request_body_size_kb = 128
  }
  
  tags = var.tags

  # Depends on the function app integration to ensure proper ordering
  depends_on = [
    azurerm_app_service_virtual_network_swift_connection.function_vnet_integration
  ]
}

# Log Analytics for App Gateway
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "appgw-diag-logs"
  target_resource_id         = azurerm_application_gateway.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}