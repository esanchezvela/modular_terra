
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
  subnet_id           = module.network_ad2022.subnets_ids[1]

  private_service_connection {
    name                           = "kv-connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.domain_join.id
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "kv_dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv-network_ad2022" {
  depends_on = [
    module.myrg,
    module.network_ad2022
  ]

  name =  "${azurerm_key_vault.domain_join.name}-network_ad2022-link"

  private_dns_zone_id = azurerm_private_dns_zone.kv.id
  virtual_network_id = module.network_ad2022.network_id

  registration_enabled = false
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv-network_servers" {
  depends_on = [
    module.myrg,
    module.network
  ]

  name =  "${azurerm_key_vault.domain_join.name}-network_servers-link"

  private_dns_zone_id = azurerm_private_dns_zone.kv.id
  virtual_network_id = module.network.network_id

  registration_enabled = false
}
