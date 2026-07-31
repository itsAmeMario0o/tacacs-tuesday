output "vm_id" {
  description = "Resource ID, used by the Bastion tunnel command"
  value       = azurerm_linux_virtual_machine.ise.id
}

output "private_ip" {
  description = "ISE management IP inside snet-mgmt"
  value       = azurerm_network_interface.ise.private_ip_address
}

output "ssh_private_key" {
  description = "Private key for iseadmin CLI access"
  value       = tls_private_key.ise.private_key_openssh
  sensitive   = true
}
