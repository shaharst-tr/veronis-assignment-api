# modules/function-app/main.tf - Function App resource definitions

locals {
  # Default and custom app settings merged
  app_settings = merge({
    FUNCTIONS_WORKER_RUNTIME       = "python"
    WEBSITE_RUN_FROM_PACKAGE       = "1"
  }, var.additional_app_settings)
  
  # Storage account default settings
  storage_network_rules = {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  # CORS default settings for public API
  cors_settings = {
    allowed_origins     = var.cors_allowed_origins
    support_credentials = var.cors_support_credentials
  }
}

# Storage account for Function App
resource "azurerm_storage_account" "func_storage" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication
  min_tls_version          = "TLS1_2"
  
  # Public access for Function App storage
  network_rules {
    default_action = local.storage_network_rules.default_action
    bypass         = local.storage_network_rules.bypass
  }
  
  tags = var.tags
}

# Application Insights for monitoring
resource "azurerm_application_insights" "func_insights" {
  name                = var.app_insights_name
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  
  tags = var.tags
}

# App Service Plan (Consumption Plan by default)
resource "azurerm_service_plan" "func_plan" {
  name                = var.app_service_plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  
  # Use consumption plan by default
  sku_name = var.app_service_plan_sku
  
  tags = var.tags
}

# Function App - configured with system-assigned identity
resource "azurerm_linux_function_app" "function_app" {
  name                       = var.function_app_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  service_plan_id            = azurerm_service_plan.func_plan.id
  storage_account_name       = azurerm_storage_account.func_storage.name
  storage_account_access_key = azurerm_storage_account.func_storage.primary_access_key
  
  site_config {
    application_stack {
      python_version = var.python_version
    }
    
    # Public API - CORS settings from variables
    cors {
      allowed_origins     = local.cors_settings.allowed_origins
      support_credentials = local.cors_settings.support_credentials
    }
    
    # Application Insights integration
    application_insights_key               = azurerm_application_insights.func_insights.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.func_insights.connection_string
    
    # Security settings
    ftps_state           = "Disabled"
    http2_enabled        = true
    minimum_tls_version  = "1.2"
  }

  # App settings - merged default and custom
  app_settings = local.app_settings
  
  # Configure identity - can be SystemAssigned, UserAssigned, or SystemAssigned, UserAssigned
  identity {
    type         = var.identity_type
    identity_ids = var.identity_type == "SystemAssigned" ? null : var.identity_ids
  }
  
  # Health check if enabled
  dynamic "site_config" {
    for_each = var.health_check_path != null ? [1] : []
    content {
      health_check_path = var.health_check_path
    }
  }
  
  tags = var.tags
}

# Storage account role assignment - now using system-assigned identity
resource "azurerm_role_assignment" "function_to_storage" {
  scope                = azurerm_storage_account.func_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.function_app.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.function_app, azurerm_storage_account.func_storage]
}