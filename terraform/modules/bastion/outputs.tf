output "bastion_name" {
  description = "Bastion host name for az network bastion tunnel commands"
  value       = azurerm_bastion_host.lab.name
}
