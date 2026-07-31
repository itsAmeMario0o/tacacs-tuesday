output "vm_id" {
  description = "Resource ID, used by the Bastion tunnel command"
  value       = azurerm_linux_virtual_machine.c8000v.id
}

output "private_ip" {
  description = "Router management IP inside snet-nad"
  value       = azurerm_network_interface.c8000v.private_ip_address
}
