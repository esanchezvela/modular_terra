
resource "azurerm_storage_account" "provisioning" {
  name                 = var.storage_account_name 
  resource_group_name  = var.rg_name 
  location             = var.location

  account_tier                    = "Standard"
  account_replication_type        = "LRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "provisioning" {
  name              = "provisioning"
  storage_account_id = azurerm_storage_account.provisioning.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "bootstrap" {
  name                 = "Bootstrap-ADDS.ps1"
  storage_account_name = azurerm_storage_account.provisioning.name
  storage_container_name = azurerm_storage_container.provisioning.name
  type           = "Block"

  source_content  = local.bootstrap_script
}

resource "azurerm_storage_blob" "post_reboot" {
  name  = "Complete-LinuxEnrollment.ps1"
  storage_account_name = azurerm_storage_account.provisioning.name
  storage_container_name = azurerm_storage_container.provisioning.name
  type = "Block"

  source_content = file("${path.module}/scripts/Complete-LinuxEnrollment.ps1")
}

resource "azurerm_storage_blob" "linux_enrollment" {
  name  = "LinuxComputerEnrollment.ps1"
  storage_account_name = azurerm_storage_account.provisioning.name
  storage_container_name = azurerm_storage_container.provisioning.name
  type           = "Block"

  source_content = local.enrollment_script
}


