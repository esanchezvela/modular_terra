
module "network_ad2022" {
  source         = "../modules/network"
  depends_on     = [module.myrg]
  name           = "network_ad2022"
  location       = var.location
  resource_group = var.rg_name
  cidr           = "10.100.0.0/16"
  cidr_bits      = var.cidr_bits
}

module "network_ad2025" {
  source         = "../modules/network"
  depends_on     = [module.myrg]
  name           = "network_ad_2025"
  location       = var.location
  resource_group = var.rg_name
  cidr           = "10.200.0.0/16"
  cidr_bits      = var.cidr_bits
}

module "network" {
  source         = "../modules/network"
  depends_on     = [module.myrg]
  name           = "servers"
  location       = var.location
  resource_group = var.rg_name
  cidr           = "10.0.0.0/16"
  cidr_bits      = var.cidr_bits
}

resource "azurerm_virtual_network_peering" "peer01" {
  name       = "peer01"
  depends_on = [module.network_ad2022, module.network_ad2025, module.myrg]

  resource_group_name       = var.rg_name
  virtual_network_name      = module.network_ad2022.network_name
  remote_virtual_network_id = module.network_ad2025.network_id
}

resource "azurerm_virtual_network_peering" "peer10" {
  name       = "peer10"
  depends_on = [module.network_ad2022, module.network_ad2025, module.myrg]

  resource_group_name       = var.rg_name
  virtual_network_name      = module.network_ad2025.network_name
  remote_virtual_network_id = module.network_ad2022.network_id
}

resource "azurerm_virtual_network_peering" "peer02" {
  name       = "peer02"
  depends_on = [module.network_ad2022, module.network, module.myrg]

  resource_group_name       = var.rg_name
  virtual_network_name      = module.network_ad2022.network_name
  remote_virtual_network_id = module.network.network_id
}

resource "azurerm_virtual_network_peering" "peer20" {
  name       = "peer20"
  depends_on = [module.network_ad2022, module.network, module.myrg]

  resource_group_name       = var.rg_name
 virtual_network_name      = module.network.network_name
  remote_virtual_network_id = module.network_ad2022.network_id
}

