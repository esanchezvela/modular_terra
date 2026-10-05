
#     azurerm_key_vault_secret.dsrm

resource "time_sleep" "controller_wait_for_dependencies" {
  depends_on = [
    azurerm_role_assignment.windows_blob_reader,
    azurerm_role_assignment.windows_key_vault_secrets_officer,

    azurerm_private_endpoint.pep_blob,
    azurerm_private_dns_zone_virtual_network_link.blob-network_ad2022,

    azurerm_private_endpoint.pep_kv,
    azurerm_private_dns_zone_virtual_network_link.kv-network_ad2022,

    azurerm_storage_blob.bootstrap.url,
    azurerm_storage_blob.post_reboot.url,
    azurerm_storage_blob.linux_enrollment.url,
    azurerm_storage_blob.reverse_zone.url
  ]

  create_duration = "60s"
}

resource "time_sleep" "linux_wait_for_dependencies" {
  depends_on = [
    azurerm_role_assignment.linux_key_vault_secrets_reader,
    azurerm_virtual_machine_extension.ad_bootstrap,
    azurerm_private_dns_zone_virtual_network_link.kv-network_servers,
    azurerm_virtual_network_dns_servers.dns_servers
  ]
  create_duration = "300s"
}
