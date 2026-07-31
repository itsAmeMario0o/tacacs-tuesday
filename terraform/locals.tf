locals {
  common_tags = {
    project = "tacacs-tuesday"
    owner   = var.owner
    expires = var.expires
  }
}
