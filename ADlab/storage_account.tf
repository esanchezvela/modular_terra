
resource "azurerm_storage_account" "provisioning" {
  depends_on = [
    module.myrg
  ]

  name                      = "${var.prefix}stg${random_id.randomId.hex}"
  resource_group_name       = var.rg_name 
  location                  = var.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access           = "Enabled"
  allow_nested_items_to_be_public = false

  tags = {
    SecurityControl = "Ignore"
  }
}

resource "azurerm_storage_container" "provisioning" {
  name              = "provisioning"
  storage_account_id = azurerm_storage_account.provisioning.id
  container_access_type = "private"
}

