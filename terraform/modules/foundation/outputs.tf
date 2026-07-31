output "resource_group_name" {
  description = "Name of the lab resource group"
  value       = azurerm_resource_group.lab.name
}

output "location" {
  description = "Region the resource group landed in"
  value       = azurerm_resource_group.lab.location
}

output "bastion_subnet_id" {
  description = "Subnet ID for AzureBastionSubnet"
  value       = azurerm_subnet.bastion.id
}

output "mgmt_subnet_id" {
  description = "Subnet ID for snet-mgmt"
  value       = azurerm_subnet.mgmt.id
}

output "nad_subnet_id" {
  description = "Subnet ID for snet-nad"
  value       = azurerm_subnet.nad.id
}
