output "ise_private_ip" {
  description = "ISE management IP"
  value       = module.ise.private_ip
}

output "c8000v_private_ip" {
  description = "Router management IP"
  value       = module.c8000v.private_ip
}

output "bastion_tunnel_commands" {
  description = "Copy-paste tunnels; each occupies a terminal"
  value = {
    ise    = "az network bastion tunnel -n ${module.bastion.bastion_name} -g ${module.foundation.resource_group_name} --target-resource-id ${module.ise.vm_id} --resource-port 443 --port 8443"
    c8000v = "az network bastion tunnel -n ${module.bastion.bastion_name} -g ${module.foundation.resource_group_name} --target-resource-id ${module.c8000v.vm_id} --resource-port 22 --port 2222"
  }
}

output "ise_admin_password" {
  description = "ISE GUI password for the admin user. Read with terraform output -raw."
  value       = random_password.ise_admin.result
  sensitive   = true
}

output "c8000v_admin_password" {
  description = "Local IOS user password. Read with terraform output -raw."
  value       = random_password.c8000v_admin.result
  sensitive   = true
}

output "tacacs_shared_secret" {
  description = "TACACS+ secret shared between ISE and the router. Read with terraform output -raw."
  value       = random_password.tacacs_secret.result
  sensitive   = true
}

output "ise_ssh_private_key" {
  description = "Key for iseadmin CLI access. Read with terraform output -raw."
  value       = module.ise.ssh_private_key
  sensitive   = true
}
