
resource "azurerm_role_assignment" "linux_key_vault_secrets_reader" {
  depends_on  =  [
                   module.myrg,
                   module.payg
                 ]

  count = length(var.payg)

  scope                = azurerm_key_vault.domain_join.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.payg[count.index].identity
  principal_type       = "ServicePrincipal"
}
