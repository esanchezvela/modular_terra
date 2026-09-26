resource "azurerm_private_dns_zone" "kv" {
  depends_on          = [module.myrg]
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.rg_name
}

resource "azurerm_private_endpoint" "pep_kv" {
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
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
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

