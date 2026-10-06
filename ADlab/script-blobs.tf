resource "azurerm_storage_blob" "bootstrap" {
  depends_on = [
    azurerm_private_endpoint.pep_blob,
    azurerm_storage_container.provisioning,
    azurerm_private_dns_zone_virtual_network_link.blob-network_ad2022
  ]

  name                   = local.bootstrap_blob_name
  storage_container_id   = azurerm_storage_container.provisioning.id
  type                   = "Block"

  source_content = local.bootstrap_script
  content_type = "text/plain"
}

resource "azurerm_storage_blob" "post_reboot" {
  depends_on = [
    azurerm_private_endpoint.pep_blob,
    azurerm_storage_container.provisioning,
    azurerm_private_dns_zone_virtual_network_link.blob-network_ad2022
  ]

  name                   = local.post_reboot_blob_name
  storage_container_id   = azurerm_storage_container.provisioning.id
  type                   = "Block"

  source_content = local.post_reboot_script
  content_type = "text/plain"
}

resource "azurerm_storage_blob" "linux_enrollment" {
  depends_on = [
    azurerm_private_endpoint.pep_blob,
    azurerm_storage_container.provisioning,
    azurerm_private_dns_zone_virtual_network_link.blob-network_ad2022
  ]

  name                   = local.enrollment_blob_name
  storage_container_id   = azurerm_storage_container.provisioning.id
  type                   = "Block"

  source_content = local.enrollment_script
  content_type = "text/plain"
}

resource "azurerm_storage_blob" "reverse_zone" {
  depends_on = [
    azurerm_private_endpoint.pep_blob,
    azurerm_storage_container.provisioning,
    azurerm_private_dns_zone_virtual_network_link.blob-network_ad2022
  ]
  name                   = "CreateReverseZone.ps1"
  storage_container_id   = azurerm_storage_container.provisioning.id
  type                   = "Block"

  source = "${path.module}/scripts/CreateReverseZone.ps1"
  content_type = "text/plain"
}
