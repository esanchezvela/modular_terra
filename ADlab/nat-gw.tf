

resource "azurerm_public_ip" "natgw_publicip" {
  name                = "nat-gateway-publicIP"
  depends_on          = [module.network, module.myrg]
  location            = var.location
  resource_group_name = var.rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "natgw" {
  name                    = "natgw"
  depends_on              = [module.network, module.myrg]
  location                = var.location
  resource_group_name     = var.rg_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
}

resource "azurerm_nat_gateway_public_ip_association" "natgw_ip" {
  nat_gateway_id       = azurerm_nat_gateway.natgw.id
  public_ip_address_id = azurerm_public_ip.natgw_publicip.id
}

resource "azurerm_subnet_nat_gateway_association" "private_network_escape" {
  depends_on     = [module.network, module.myrg]
  subnet_id      = module.network.subnets_ids[0]
  nat_gateway_id = azurerm_nat_gateway.natgw.id
}

