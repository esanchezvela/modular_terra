locals {

  computer_names = [
    for vm in var.payg : upper(trimspace(vm.name))
  ]

  dsrm_secret_name      = "ad-dsrm-password"
  blob_container_name   = "provisioning"

  bootstrap_blob_name   = "Bootstrap-ADDS.ps1"
  post_reboot_blob_name = "Complete-LinuxEnrollment.ps1"
  enrollment_blob_name  = "LinuxComputerEnrollment.ps1"

  enrollment_script = templatefile(
    "${path.module}/scripts/LinuxComputerEnrollment.ps1.tftpl",
    {
      COMPUTER_NAMES_JSON = jsonencode(local.computer_names)
      COMPUTER_OU         = jsonencode(var.computer_ou)
      KEY_VAULT_NAME      = jsonencode(azurerm_key_vault.domain_join.name)
      SUBSCRIPTION_ID     = jsonencode(data.azurerm_client_config.current.subscription_id)
      LOG_FILE            = jsonencode("C:\\Temp\\Linux-Computer-Provisioning.log")
    }
  )


  domain_join_script_here = <<-HERE
    #!/bin/bash
    set -euo pipefail
    /opt/vm-deployment/restart_network.sh && /opt/vm-deployment/venv/bin/python /opt/vm-deployment/deploy.py --domain $${custom_domain} \
              --computer_ou $${computer_ou} \
              --vault $${vault_name}
  HERE
  domain_join_script = templatestring(local.domain_join_script_here, {
         vault_name = azurerm_key_vault.domain_join.name,
         computer_ou = var.computer_ou,
         custom_domain = var.custom_domain 
     }
  )

  post_reboot_script = file("${path.module}/scripts/Complete-LinuxEnrollment.ps1")
  bootstrap_script = templatefile("${path.module}/scripts/Bootstrap-ADDS.ps1.tftpl",
    {
      DOMAIN_NAME         = jsonencode(var.custom_domain)
      DOMAIN_NETBIOS_NAME = jsonencode(upper(var.domain_netbios_name))
      SUBSCRIPTION_ID     = jsonencode(data.azurerm_client_config.current.subscription_id)
      DSRM_VAULT_NAME     = jsonencode(azurerm_key_vault.domain_join.name)
      DSRM_SECRET_NAME    = jsonencode(local.dsrm_secret_name)
    }
  )

  artifact_hash = sha256(
    join("|",
      [
        local.bootstrap_script,
        local.post_reboot_script,
        local.enrollment_script
      ]
    )
  )

  #
  # Custom Script Extension timestamp must be a signed 32-bit integer.
  #
  extension_timestamp = parseint(substr(local.artifact_hash, 0, 7), 16)
}
