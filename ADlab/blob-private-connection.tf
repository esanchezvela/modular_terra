################################################################################
# Blob Private DNS Zone
#
#
# <storage-account>.blob.core.windows.net
#
# resolves through the Storage private endpoint from the linked VNet.
################################################################################

resource "azurerm_private_dns_zone" "blob" {

  depends_on          = [module.myrg]

  name = "privatelink.blob.core.windows.net"
  resource_group_name = var.rg_name
}

resource "azurerm_private_endpoint" "pep_blob" {
  depends_on = [
    module.myrg,
    module.network_ad2022
  ]

  name        = "blob-pep"
  location    = var.location
  resource_group_name = var.rg_name
  subnet_id   = module.network_ad2022.subnets_ids[0]

  private_service_connection {
    name             = "blob-connection"
    is_manual_connection  = false
    private_connection_resource_id  = azurerm_storage_account.provisioning.id
    subresource_names = ["blob"]
  }

  private_dns_zone_group {
    name              = "blob_dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

################################################################################
# Link Private DNS Zone to VNET
################################################################################
resource "azurerm_private_dns_zone_virtual_network_link" "blob-network_ad2022" {
  depends_on = [
    module.myrg,
    module.network_ad2022
  ]

  name = "${azurerm_storage_account.provisioning.name}-network_ad2022-link"

  private_dns_zone_id = azurerm_private_dns_zone.blob.id
  virtual_network_id = module.network_ad2022.network_id

  registration_enabled = false
}

################################################################################
# Link Private DNS Zone to VNET
################################################################################
resource "azurerm_private_dns_zone_virtual_network_link" "blob-network_servers" {
  depends_on = [
    module.myrg,
    module.network
  ]

  name = "${azurerm_storage_account.provisioning.name}-network_servers-link"

  private_dns_zone_id = azurerm_private_dns_zone.blob.id
  virtual_network_id = module.network.network_id

  registration_enabled = false
}
