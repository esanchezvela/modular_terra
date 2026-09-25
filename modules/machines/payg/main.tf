
resource "azurerm_public_ip" "public_ip_address" {
    count    =  var.pubip ? 1 : 0
    name   = "${var.name}-public-ip"
    location = var.location
    resource_group_name = var.resource_group
    allocation_method   = "Static"
    sku                 = "Standard"
    ip_version          = "IPv4"
}

resource "azurerm_network_interface" "nics" {
  count = var.nics  
  name                    = "${var.name}-eth${count.index}" 
  location                = var.location
  resource_group_name     = var.resource_group
  dns_servers             = var.dns_server 
  accelerated_networking_enabled = var.network_acceleration

  ip_configuration {
    name                           = "${var.name}-eth${count.index}_priv"
    subnet_id                      = var.nic_subnetid[count.index]
    private_ip_address_allocation  = "Static"
    private_ip_address             = cidrhost(var.cidr_list[count.index], var.priv_index)
    primary                        = "true"
    public_ip_address_id           = var.pubip && count.index == 0 ? azurerm_public_ip.public_ip_address[0].id : null
  }
}

resource "azurerm_linux_virtual_machine" "machine" {
    name                   = var.name
    location               = var.location
    resource_group_name    = var.resource_group
    network_interface_ids  = azurerm_network_interface.nics[*].id 
    size                   = var.size

    computer_name          = var.name
    admin_username         = "azureuser"
    custom_data            = var.custom_data
    disk_controller_type   = var.disk_controller_type
    availability_set_id    = var.avsetid 

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
      disk_size_gb = var.publisher == "microsoftcblmariner" ? 30 : null
    }

    admin_ssh_key {
      username    = "azureuser"
      public_key  = file(var.pubkey)
    }

    boot_diagnostics {
        storage_account_uri = var.storage_account
    }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "schedule" {
    virtual_machine_id = azurerm_linux_virtual_machine.machine.id
    location           = azurerm_linux_virtual_machine.machine.location
    enabled            = true 

    daily_recurrence_time = "0100"
    timezone              = "UTC"

    notification_settings {
        enabled     = false
    }
}


output "machine" {
  value = azurerm_linux_virtual_machine.machine
}

output "ip_address" {
  value = var.pubip ? azurerm_public_ip.public_ip_address[0].ip_address : null
}

output "identity" {
  value = azurerm_linux_virtual_machine.machine.identity[0].principal_id
}
