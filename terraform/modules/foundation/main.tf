resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "lab" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

# Bastion requires this exact subnet name. It gets no NSG on purpose:
# attaching one requires Microsoft's mandatory rule set and is the most
# common way Bastion gets broken (ADR 0002).
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.bastion_subnet_cidr]
}

resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.mgmt_subnet_cidr]
}

resource "azurerm_subnet" "nad" {
  name                 = "snet-nad"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.nad_subnet_cidr]
}

# ADR 0002: keep the Azure default rules, which already allow VNet-internal
# traffic and deny internet inbound. The explicit rules below duplicate the
# defaults for the flows the demo depends on, so intent is documented and
# nothing can break east-west traffic.
resource "azurerm_network_security_group" "mgmt" {
  name                = "${var.name_prefix}-nsg-mgmt"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  security_rule {
    name                       = "AllowTacacsFromVnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "49"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHttpsFromVnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSshFromVnet"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "nad" {
  name                = "${var.name_prefix}-nsg-nad"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = var.tags

  security_rule {
    name                       = "AllowSshFromVnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

resource "azurerm_subnet_network_security_group_association" "nad" {
  subnet_id                 = azurerm_subnet.nad.id
  network_security_group_id = azurerm_network_security_group.nad.id
}
