locals {
  computer_names = [
   for vm in var.payg: vm.name 
  ]

  enrollment_script = templatefile(
    "${path.module}/LinuxComputerEnrollment.ps1.tftpl",
    {
      COMPUTER_NAMES_JSON = jsonencode(jsonencode(local.computer_names))
      COMPUTER_OU         = jsonencode(var.computer_ou)
      KEY_VAULT_NAME      = jsonencode(azurerm_key_vault.domain_join.name)
      SUBSCRIPTION_ID     = jsonencode(data.azurerm_client_config.current.subscription_id)
      LOG_FILE            = jsonencode("C:\\Logs\\Linux-Computer-Provisioning.log")
    }
  )

  post_reboot_script = file(
    "${path.module}/Complete-LinuxEnrollment.ps1"
  )

  bootstrap_script = templatefile(
    "${path.module}/Bootstrap-ADDS.ps1.tftpl",
    {
      DOMAIN_NAME              = jsonencode(var.custom_domain)
      DOMAIN_NETBIOS_NAME      = jsonencode(var.domain_netbios_name)
      SUBSCRIPTION_ID          = jsonencode(data.azurerm_client_config.current.subscription_id)
      DSRM_VAULT_NAME          = jsonencode(azurerm_key_vault.domain_join.name)
      DSRM_SECRET_NAME         = jsonencode(azurerm_key_vault_secret.dsrm.name)
      ENROLLMENT_SCRIPT_BASE64 = jsonencode(base64encode(local.enrollment_script))
      POST_REBOOT_SCRIPT_BASE64 = jsonencode(base64encode(local.post_reboot_script))
    }
  )
}

resource "azurerm_virtual_machine_extension" "ad_bootstrap" {
  name               = "ADDS-Bootstrap"
  virtual_machine_id = module.controller22.machineid

  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

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
