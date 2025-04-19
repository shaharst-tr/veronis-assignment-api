# Key Vault Module
# Creates an Azure Key Vault for storing secrets

resource "azurerm_key_vault" "main" {
  name                        = var.key_vault_name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  enable_rbac_authorization   = false
  
  # Standard SKU provides adequate performance for most needs
  sku_name = "standard"
  
  # Configure network access controls
  network_acls {
    default_action = var.network_acls_default_action
    bypass         = var.network_acls_bypass
    ip_rules       = var.allowed_ip_ranges
  }
  
  tags = var.tags
}

# Access policy for the current client (Terraform)
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  
  # Permissions needed for terraform management
  certificate_permissions = [
    "Backup",
    "Create", 
    "Delete", 
    "DeleteIssuers", 
    "Get", 
    "GetIssuers", 
    "Import", 
    "List", 
    "ListIssuers", 
    "ManageContacts", 
    "ManageIssuers", 
    "Purge", 
    "Recover", 
    "Restore", 
    "SetIssuers", 
    "Update"
  ]
  
  key_permissions = [
    "Backup", 
    "Create", 
    "Decrypt", 
    "Delete", 
    "Encrypt", 
    "Get", 
    "Import", 
    "List", 
    "Purge", 
    "Recover", 
    "Restore", 
    "Sign", 
    "UnwrapKey", 
    "Update", 
    "Verify", 
    "WrapKey"
  ]
  
  secret_permissions = [
    "Backup", 
    "Delete", 
    "Get", 
    "List", 
    "Purge", 
    "Recover", 
    "Restore", 
    "Set"
  ]
}

# Get current client configuration for access policy
data "azurerm_client_config" "current" {}