

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

resource "random_password" "dsrm" {
  length = 32

   upper = true
   lower = true
   numeric = true
   special = true

   override_special = "!#$%&*+-.:=?@_"
}

resource "azurerm_key_vault_secret" "dsrm" {
  name   = local.dsrm_secret_name
  value  = random_password.dsrm.result
  key_vault_id = azurerm_key_vault.domain_join.id

  content_type = "Active Directory DSRM password"

  tags = {
    Purpose = "Active-Directory-DSRM"
  }
}

