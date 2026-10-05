resource "azurerm_virtual_machine_extension" "ad_computer_join" {
  depends_on  = [ 
    module.payg,
    azurerm_role_assignment.linux_key_vault_secrets_reader,
    time_sleep.linux_wait_for_dependencies
  ]

  count = length(var.payg)

  name               = "Domain_join-Extension"
  virtual_machine_id = module.payg[count.index].machine.id

  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"

  auto_upgrade_minor_version = true

  settings = jsonencode({
    script = base64encode(local.domain_join_script)
  })

}
