
#module "controller25" {
#  source = "../modules/machines/adc"
#  depends_on = [
#    module.myrg,
#    azurerm_subnet_network_security_group_association.network_ad2022_nsg_asocc,
#    module.network_ad2025
#  ]
#
#  server_name   = "controller25"
#  nic0_ip       = cidrhost(module.network_ad2025.subnets_cidrs[0], 5)
#  nic0_subnetid = module.network_ad2025.subnets_ids[0]
#
#  pubip         = true
#  publisher     = "MicrosoftWindowsServer"
#  offer         = "WindowsServer"
#  sku           = "2025-datacenter-g2"
#  image_version = "latest"
#
#  userpassword = var.userpassword
#
#  size = "Standard_D4s_v4"
#
#  resource_group  = var.rg_name
#  storage_account = null
#  location        = var.location
#  adsetup         = true
#  custom_domain   = "AD25.NEWXYZ.SITE"
#
#}

module "controller22" {
  source = "../modules/machines/adc"
  depends_on = [
    module.myrg,
    azurerm_subnet_network_security_group_association.network_ad2022_nsg_asocc,
    module.network_ad2022
  ]

  server_name   = "controller22"
  nic0_ip       = cidrhost(module.network_ad2022.subnets_cidrs[0], 5)
  nic0_subnetid = module.network_ad2022.subnets_ids[0]

  pubip         = true
  publisher     = "MicrosoftWindowsServer"
  offer         = "WindowsServer"
  sku           = "2022-datacenter-g2"
  image_version = "latest"

  userpassword = var.userpassword

  size = "Standard_D4s_v4"

  storage_account = null
  resource_group  = var.rg_name
  location        = var.location
  adsetup         = true
  custom_domain   = var.custom_domain

}

module "jumphost" {

  source = "../modules/machines/payg"
  depends_on = [
    module.myrg,
    module.network_ad2022,
  ]

  name         = "jumphost"
  priv_index   = 7
  cidr_list    = module.network_ad2022.subnets_cidrs
  nic_subnetid = module.network_ad2022.subnets_ids

  pubip         = true
  publisher     = "canonical"
  offer         = "ubuntu-24_04-lts"
  sku           = "server"
  image_version = "latest"

  size                 = "Standard_D2s_v4"
  network_acceleration = false
  nics                 = 1
  disk_controller_type = "SCSI"

  encrypt = false

  resource_group = var.rg_name
  location       = var.location

}

output "jumphostip" {
  value = "jumpserver IP ${module.jumphost.ip_address}"
}
