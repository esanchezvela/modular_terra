resource "azurerm_virtual_machine_extension" "ad_bootstrap" {
  depends_on  = [ 
    time_sleep.wait_for_dependencies,
    module.controller22
  ]

  name               = "ADDS-Bootstrap"
  virtual_machine_id = module.controller22.machineid

  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    timestamp = local.extension_timestamp
  })

  protected_settings = jsonencode({
    fileUris = [
      azurerm_storage_blob.bootstrap.url,
      azurerm_storage_blob.post_reboot.url,
      azurerm_storage_blob.linux_enrollment.url
    ]

    commandToExecute = join(
      " ",
      [
        "powershell.exe",
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy Bypass",
        "-File .\\${local.bootstrap_blob_name}"
      ]
    )

    #
    # Empty object selects the VM's system-assigned managed identity.
    #
    managedIdentity = {}
  })

}
