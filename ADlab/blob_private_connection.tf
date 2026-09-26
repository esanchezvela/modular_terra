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

resource "azurerm_private_endpoint" "pep_stg" {
  depends_on = [
    module.myrg,
    module.network_ad2022
  ]

  name        = "stg-pep"
  location    = var.location
  resource_group_name = var.rg_name
  subnet_id   = module.network_ad2022.subnets_ids[0]

  private_service_connection {
    name             = "stg-connection"
    is_manual_connection  = false
    private_connection_resource_id  = azurerm_storage_account.provisioning.id
    subresourc_names = ["blob"]
  }

  private_dns_zone_group {
    name              = "stg-dns-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

################################################################################
# Link Private DNS Zone to VNET
################################################################################
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name = "${var.storage_account_name}-blob-vnet-link"

  resource_group_name = var.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name

  virtual_network_id = var.virtual_network_id

  registration_enabled = false
}
























