
resource "azurerm_public_ip" "public_ip_address" {
    count    =  var.pubip ? 1 : 0
    name   = "${var.server_name}-public-ip"
    location = var.location
    resource_group_name = var.resource_group
    allocation_method   = "Static"
    sku                 = "Standard"
    ip_version          = "IPv4"
}

resource "azurerm_network_interface" "nic0" {
  name                    = "${var.server_name}-eth0" 
  location                = var.location
  resource_group_name     = var.resource_group

  ip_configuration {
    name                           = "${var.server_name}-eth0_priv"
    subnet_id                      = var.nic0_subnetid
    private_ip_address_allocation  = "Static"
    private_ip_address             = var.nic0_ip
    primary                        = "true"
    public_ip_address_id           = var.pubip ? azurerm_public_ip.public_ip_address[0].id : null
  }
}

resource "azurerm_windows_virtual_machine" "machine" {
    name                   = var.server_name
    location               = var.location
    resource_group_name    = var.resource_group
    network_interface_ids  = [azurerm_network_interface.nic0.id]
    size                   = var.size

    computer_name          = var.server_name
    admin_username         = "azureadmin"
    admin_password         = var.userpassword

    identity {
      type = "SystemAssigned"
    }

    source_image_reference {
      publisher   = var.publisher
      offer       = var.offer
      sku         = var.sku
      version     = var.image_version
    }

    os_disk {
      caching              = "None"
      storage_account_type = "Standard_LRS"
    }
    
    boot_diagnostics {
        storage_account_uri = var.storage_account
    }
}

data template_file "adcsetup" {
    template = file("${path.module}/scripts/customscript.ps1")
    vars = {
        DOMAIN = var.custom_domain
    }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "schedule" {
    virtual_machine_id = azurerm_windows_virtual_machine.machine.id
    location           = azurerm_windows_virtual_machine.machine.location
    enabled            = true 

    daily_recurrence_time = "0100"
    timezone              = "UTC"

    notification_settings {
        enabled     = false
    }
}

output "machineid" {
 value = azurerm_windows_virtual_machine.machine.id 
}

output "ip_address" {
  value = var.pubip ? azurerm_public_ip.public_ip_address[0].ip_address : null
}

output "identity" {
  value = azurerm_windows_virtual_machine.machine.identity[0].principal_id
}

output "priv_address" {
  value = var.nic0_ip
}
