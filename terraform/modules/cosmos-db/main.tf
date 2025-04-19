# modules/cosmos-db/main.tf - Cosmos DB resources

locals {
  # Secret names for consistency
  secret_names = {
    endpoint = "cosmos-endpoint"
    key      = "cosmos-key"
  }
}

resource "azurerm_cosmosdb_account" "db" {
  name                = var.cosmos_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  
  consistency_policy {
    consistency_level = var.consistency_level
  }
  
  geo_location {
    location          = var.location
    failover_priority = 0
  }
  
  # Use serverless or provisioned capacity mode based on variable
  dynamic "capabilities" {
    for_each = var.enable_serverless ? [1] : []
    content {
      name = "EnableServerless"
    }
  }
  
  # Default to public access for simplified setup
  public_network_access_enabled = var.public_network_access_enabled
  
  tags = var.tags
}

resource "azurerm_cosmosdb_sql_database" "db" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.db.name
}

resource "azurerm_cosmosdb_sql_container" "container" {
  name                = var.container_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.db.name
  database_name       = azurerm_cosmosdb_sql_database.db.name
  partition_key_paths  = [var.partition_key_path]
  
  # Add optional indexing policy if specified
  dynamic "indexing_policy" {
    for_each = var.indexing_policy != null ? [var.indexing_policy] : []
    content {
      indexing_mode = indexing_policy.value.indexing_mode
      
      dynamic "included_path" {
        for_each = indexing_policy.value.included_paths
        content {
          path = included_path.value
        }
      }
      
      dynamic "excluded_path" {
        for_each = indexing_policy.value.excluded_paths
        content {
          path = excluded_path.value
        }
      }
    }
  }
}