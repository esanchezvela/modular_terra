
resource "azurerm_virtual_machine_extension" "ad_bootstrap" {
  name               = "ADDS-Bootstrap"
  virtual_machine_id = module.controller22.machineid

  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = join(" ", [
      "powershell.exe",
      "-NoLogo",
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy Bypass",
      "-EncodedCommand",
      textencodebase64(local.bootstrap_script, "UTF-16LE")
    ])
  })

  depends_on = [
    module.controller22,
    azurerm_key_vault_secret.dsrm,
    azurerm_role_assignment.windows_secrets_officer
  ]
}
