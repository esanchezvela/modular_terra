

resource "azurerm_role_assignment" "windows_secrets_officer" {
  depends_on  =  [
                   module.myrg,
                   module.controller22
                 ]

  scope                = azurerm_key_vault.domain_join.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = module.controller22.identity
}
