# main.tf - Provider configuration and main resources 

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0" 
    }
  }
  
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstaterestaurantapi"
    container_name       = "tfstate"
    key                  = "restaurant-api.tfstate"
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

locals {
  # Naming convention
  name_prefix = "${var.project_name}"
  
  # Resource-specific names
  names = {
    resource_group  = "${local.name_prefix}-rg"
    key_vault       = "${local.name_prefix}-kv"
    cosmos_account  = "${local.name_prefix}-cosmos"
    function_app    = "${local.name_prefix}-func"
    storage_account = lower(replace("${var.project_name}${var.environment}sa", "-", ""))
    app_insights    = "${local.name_prefix}-insights"
    app_plan        = "${local.name_prefix}-plan"
    logs_workspace  = "${local.name_prefix}-logs"
  }
  
  # Database configuration
  cosmos_config = {
    database_name   = var.cosmos_db_name
    container_name  = var.cosmos_container_name
    partition_key   = "/style"
  }
  
  # Common tags that apply to all resources
  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    terraform   = "true"
  })
  
  # Function app settings - updated to use the correct secret names
  function_app_settings = {
    COSMOS_DATABASE   = "@Microsoft.KeyVault(SecretUri=${module.key_vault.key_vault_uri}secrets/CosmosDatabase/)"
    COSMOS_CONTAINER  = "@Microsoft.KeyVault(SecretUri=${module.key_vault.key_vault_uri}secrets/CosmosContainer/)"
    COSMOS_ENDPOINT   = "@Microsoft.KeyVault(SecretUri=${module.key_vault.key_vault_uri}secrets/cosmos-endpoint/)"
    COSMOS_KEY        = "@Microsoft.KeyVault(SecretUri=${module.key_vault.key_vault_uri}secrets/cosmos-key/)"
    BLOB_STORAGE_CONN = "@Microsoft.KeyVault(SecretUri=${module.key_vault.key_vault_uri}secrets/BlobStorageConnStr/)"
    BLOB_CONTAINER    = "@Microsoft.KeyVault(SecretUri=${module.key_vault.key_vault_uri}secrets/BlobContainerName/)"
    KEY_VAULT_URL     = module.key_vault.key_vault_uri
  }
}

#################################################
# Resource Group
#################################################
resource "azurerm_resource_group" "rg" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.common_tags
}

#################################################
# Key Vault
#################################################
module "key_vault" {
  source = "./modules/key-vault"

  key_vault_name      = local.names.key_vault
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  
  # Network settings
  network_acls_default_action = var.key_vault_network_default_action
  network_acls_bypass         = var.key_vault_network_bypass
  allowed_ip_ranges           = var.allowed_ip_ranges
  
  tags = local.common_tags
}

#################################################
# Cosmos DB
#################################################
module "cosmos_db" {
  source = "./modules/cosmos-db"
  
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  cosmos_account_name = local.names.cosmos_account
  database_name       = local.cosmos_config.database_name
  container_name      = local.cosmos_config.container_name
  partition_key_path  = local.cosmos_config.partition_key
  
  # Store secrets in Key Vault
  key_vault_id        = module.key_vault.key_vault_id
  
  tags = local.common_tags
  
  depends_on = [
    module.key_vault
  ]
}

# Cosmos DB secrets
resource "azurerm_key_vault_secret" "cosmos_endpoint" {
  name         = "cosmos-endpoint"
  value        = module.cosmos_db.cosmos_db_endpoint
  key_vault_id = module.key_vault.key_vault_id
  
  depends_on = [
    module.key_vault,
    module.cosmos_db
  ]
}

resource "azurerm_key_vault_secret" "cosmos_key" {
  name         = "cosmos-key"
  value        = module.cosmos_db.cosmos_db_primary_key
  key_vault_id = module.key_vault.key_vault_id
  
  depends_on = [
    module.key_vault,
    module.cosmos_db
  ]
}

resource "azurerm_key_vault_secret" "cosmos_database" {
  name         = "CosmosDatabase"
  value        = module.cosmos_db.database_name
  key_vault_id = module.key_vault.key_vault_id
  
  depends_on = [
    module.key_vault,
    module.cosmos_db
  ]
}

resource "azurerm_key_vault_secret" "cosmos_container" {
  name         = "CosmosContainer"
  value        = module.cosmos_db.container_name
  key_vault_id = module.key_vault.key_vault_id
  
  depends_on = [
    module.key_vault,
    module.cosmos_db
  ]
}

#################################################
# Function App
#################################################
module "function_app" {
  source = "./modules/function-app"
  
  resource_group_name   = azurerm_resource_group.rg.name
  location              = var.location
  function_app_name     = local.names.function_app
  storage_account_name  = local.names.storage_account
  app_insights_name     = local.names.app_insights
  app_service_plan_name = local.names.app_plan

  # Changed to system-assigned identity
  identity_type         = "SystemAssigned"
  
  # App settings - reference secrets from Key Vault
  additional_app_settings = local.function_app_settings
  
  tags = local.common_tags
  
  depends_on = [
    module.key_vault,
    module.cosmos_db
  ]
}

# Add Function App's identity to Key Vault access policies
resource "azurerm_key_vault_access_policy" "function_access_policy" {
  key_vault_id = module.key_vault.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = module.function_app.function_app_principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
  
  depends_on = [
    module.key_vault,
    module.function_app
  ]
}

# Create a blob container in the function app's storage account
resource "azurerm_storage_container" "function_container" {
  name                  = "function-data"
  storage_account_name  = module.function_app.storage_account_name
  container_access_type = "private"
  
  depends_on = [
    module.function_app
  ]
}

# Blob storage secrets
resource "azurerm_key_vault_secret" "blob_storage_conn_str" {
  name         = "BlobStorageConnStr"
  value        = module.function_app.storage_account_connection_string
  key_vault_id = module.key_vault.key_vault_id
  
  depends_on = [
    module.key_vault,
    module.function_app
  ]
}

resource "azurerm_key_vault_secret" "blob_container_name" {
  name         = "BlobContainerName"
  value        = azurerm_storage_container.function_container.name
  key_vault_id = module.key_vault.key_vault_id
  
  depends_on = [
    module.key_vault,
    azurerm_storage_container.function_container
  ]
}

# Add role assignment for Cosmos DB data access
resource "azurerm_cosmosdb_sql_role_assignment" "function_cosmos_data_contributor" {
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = module.cosmos_db.cosmos_db_name
  role_definition_id  = "${module.cosmos_db.cosmos_db_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002" # Built-in Data Contributor role
  principal_id        = module.function_app.function_app_principal_id
  scope               = module.cosmos_db.cosmos_db_id
  
  depends_on = [
    module.cosmos_db,
    module.function_app
  ]
}

#################################################
# Log Analytics
#################################################
resource "azurerm_log_analytics_workspace" "logs" {
  name                = local.names.logs_workspace
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days
  
  tags = local.common_tags
}

# Diagnostic settings for Function App
resource "azurerm_monitor_diagnostic_setting" "function_logs" {
  name                       = "function-diagnostic-logs"
  target_resource_id         = module.function_app.function_app_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  
  enabled_log {
    category = "FunctionAppLogs"
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

#################################################
# Admin API Key
#################################################
resource "azurerm_key_vault_secret" "admin_api_key" {
  name         = "admin-api-key"
  value        = uuid() # Generate a unique API key
  key_vault_id = module.key_vault.key_vault_id
  
  depends_on = [
    module.key_vault
  ]
}

#################################################
# SSL Certificate for Application Gateway
#################################################
resource "azurerm_key_vault_certificate" "appgw_cert" {
  name         = "appgw-ssl-cert"
  key_vault_id = module.key_vault.key_vault_id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      # Generate a certificate valid for 1 year
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject            = "CN=${local.names.function_app}.azurewebsites.net"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = [
          "${local.names.function_app}.azurewebsites.net",
        ]
      }
    }
  }

  depends_on = [
    module.key_vault
  ]
}

#################################################
# Application Gateway Identity
#################################################
resource "azurerm_user_assigned_identity" "appgw" {
  name                = "id-appgw-${var.project_name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  
  tags = local.common_tags
}

# Grant the Application Gateway identity access to Key Vault
resource "azurerm_key_vault_access_policy" "appgw_access_policy" {
  key_vault_id = module.key_vault.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.appgw.principal_id
  
  secret_permissions = [
    "Get",
    "List"
  ]
  
  certificate_permissions = [
    "Get",
    "List"
  ]
  
  depends_on = [
    module.key_vault,
    azurerm_user_assigned_identity.appgw
  ]
}

#################################################
# Networking with Application Gateway
#################################################
module "networking" {
  source = "./modules/networking"
  
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = var.location
  function_app_hostname      = module.function_app.function_app_hostname
  function_app_id            = module.function_app.function_app_id
  function_app_name          = local.names.function_app
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
  
  # WAF Mode - Start with Detection, then move to Prevention after testing
  waf_mode                   = "Detection"
  
  # Key Vault certificate reference
  key_vault_secret_id        = azurerm_key_vault_certificate.appgw_cert.secret_id
  
  # Application Gateway managed identity
  appgw_identity_id          = azurerm_user_assigned_identity.appgw.id
  
  tags = local.common_tags
  
  depends_on = [
    module.function_app,
    azurerm_log_analytics_workspace.logs,
    azurerm_key_vault_certificate.appgw_cert,
    azurerm_key_vault_access_policy.appgw_access_policy
  ]
}