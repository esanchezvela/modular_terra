

resource "azurerm_role_assignment" "windows_key_vault_secrets_officer" {
  depends_on  =  [
                   module.myrg,
                   module.controller22
                 ]

  scope                = azurerm_key_vault.domain_join.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = module.controller22.identity
  principal_type       = "ServicePrincipal"
}


resource "azurerm_role_assignment" "windows_blob_reader" {
  depends_on  =  [
                   module.myrg,
                   module.controller22
                 ]

  scope                = azurerm_storage_account.provisioning.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.controller22.identity
  principal_type       = "ServicePrincipal"
}
