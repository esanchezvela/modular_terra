
resource "time_sleep" "wait_for_dependencies" {
  depends_on = [
    azurerm_role_assignment.windows_blob_reader,
    azurerm_role_assignment.windows_key_vault_secrets_officer,

    azurerm_private_endpoint.blob,
    azurerm_private_dns_zone_virtual_network_link.blob,

    azurerm_private_endpoint.pep_kv,
    azurerm_private_dns_zone_virtual_network_link.kvlink,

    azurerm_storage_blob.bootstrap,
    azurerm_storage_blob.post_reboot,
    azurerm_storage_blob.linux_enrollment,

    azurerm_key_vault_secret.dsrm
  ]

  create_duration = "30s"
}
