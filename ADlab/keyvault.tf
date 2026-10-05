

resource "azurerm_key_vault" "domain_join" {

  depends_on          = [module.myrg]

  name                = "${var.prefix}vault${random_id.randomId.hex}"
  location            = var.location
  resource_group_name = var.rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  purge_protection_enabled        = true
  soft_delete_retention_days      = 7
  rbac_authorization_enabled      = true
  tags = {
    SecurityControl = "Ignore"
  }
}
