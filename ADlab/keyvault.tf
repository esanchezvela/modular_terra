

data "azurerm_client_config" "current" {}

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

resource "azurerm_private_dns_zone" "dns" {
  depends_on          = [module.myrg]
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.rg_name
}

resource "azurerm_private_endpoint" "pep" {
  depends_on = [
    module.myrg,
    module.network_ad2022
  ]
  name                = "kv-pep"
  location            = var.location
  resource_group_name = var.rg_name
  subnet_id           = module.network_ad2022.subnets_ids[0]

  private_service_connection {
    name                           = "kv-connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.domain_join.id
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns.id]
  }
}

resource "azurerm_role_assignment" "windows_secrets_officer" {
  depends_on  =  [
                   module.myrg,
                   module.controller22
                 ]

  scope                = azurerm_key_vault.domain_join.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = module.controller22.identity
}

resource "random_password" "dsrm" {
  length = 32

   upper = true
   lower = true
   numeric = true
   special = true

   override_special = "!#$%&*+-.:=?@_"
}

locals {
  dsrm_secret_name = "ad-dsrm-password"
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

