# ISE parses its admin password from a key=value line in custom_data, where
# "#" begins a comment and would truncate the value. Restrict specials to a
# single safe character that ISE accepts and the parser leaves intact.
resource "random_password" "ise_admin" {
  length           = 16
  special          = true
  override_special = "@"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

# Azure enforces three of four character classes on admin_password.
# Force one of each present class so no rebuild draws an all-one-class
# password and fails at apply (ADR 0004 rebuild reliability).
resource "random_password" "c8000v_admin" {
  length      = 16
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "random_password" "tacacs_secret" {
  length  = 24
  special = false
}

# One SSH keypair per device, written to keys/ at the repo root so every
# login path uses the same files (ADR 0007). RSA because Azure rejects
# Ed25519 for the admin user on Cisco images. The files are Terraform
# resources, so terraform destroy deletes them with the VMs they open.
resource "tls_private_key" "c8000v_admin" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_private_key" "ise_admin" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  keys_dir = "${path.module}/../keys"
}

resource "local_sensitive_file" "c8000v_private_key" {
  content         = tls_private_key.c8000v_admin.private_key_openssh
  filename        = "${local.keys_dir}/c8000v_admin"
  file_permission = "0600"
}

resource "local_file" "c8000v_public_key" {
  content         = tls_private_key.c8000v_admin.public_key_openssh
  filename        = "${local.keys_dir}/c8000v_admin.pub"
  file_permission = "0644"
}

resource "local_sensitive_file" "ise_private_key" {
  content         = tls_private_key.ise_admin.private_key_openssh
  filename        = "${local.keys_dir}/ise_admin"
  file_permission = "0600"
}

resource "local_file" "ise_public_key" {
  content         = tls_private_key.ise_admin.public_key_openssh
  filename        = "${local.keys_dir}/ise_admin.pub"
  file_permission = "0644"
}

module "foundation" {
  source = "./modules/foundation"

  name_prefix = var.name_prefix
  location    = var.location
  tags        = local.common_tags
}

module "bastion" {
  source = "./modules/bastion"

  resource_group_name = module.foundation.resource_group_name
  location            = module.foundation.location
  bastion_subnet_id   = module.foundation.bastion_subnet_id
  tags                = local.common_tags
}

# ISE is created outside Terraform, by scripts/90-ise-deploy.sh via the az CLI.
# ISE's day-0 bootstrap is finicky enough that a 20-minute Terraform rebuild per
# attempt is too slow to iterate on. The script reuses the Terraform-built
# network and reads the admin password from the random_password below, so the
# secret still lives in one place. random_password.ise_admin is intentionally
# kept for that reason.
# module "ise" {
#   source = "./modules/ise"
#
#   resource_group_name = module.foundation.resource_group_name
#   location            = module.foundation.location
#   subnet_id           = module.foundation.mgmt_subnet_id
#   private_ip          = var.ise_private_ip
#   vm_size             = var.ise_vm_size
#   image               = var.ise_image
#   admin_password      = random_password.ise_admin.result
#   dns_server          = var.dns_server
#   tags                = local.common_tags
# }

module "c8000v" {
  source = "./modules/c8000v"

  resource_group_name = module.foundation.resource_group_name
  location            = module.foundation.location
  subnet_id           = module.foundation.nad_subnet_id
  vm_size             = var.c8000v_vm_size
  image               = var.c8000v_image
  admin_password      = random_password.c8000v_admin.result
  admin_public_key    = tls_private_key.c8000v_admin.public_key_openssh
  tacacs_secret       = random_password.tacacs_secret.result
  ise_ip              = var.ise_private_ip
  tags                = local.common_tags
}
