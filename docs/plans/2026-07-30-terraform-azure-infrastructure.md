# Terraform Azure Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Azure lab for tacacs-tuesday: Cisco ISE and a Catalyst 8000V behind Bastion tunnels, fully rebuildable with one `terraform apply`.

**Architecture:** One resource group in eastus2 holding one VNet with three subnets, per ADR 0001. Four Terraform modules (`foundation`, `bastion`, `ise`, `c8000v`) wired by a root module that generates all secrets and prints the Bastion tunnel commands. NSGs are permissive but present per ADR 0002. Marketplace images are resolved by script and pinned in a gitignored tfvars file per ADR 0005.

**Tech Stack:** Terraform >= 1.9 with azurerm ~> 4.0, random ~> 3.6, tls ~> 4.0. Azure CLI for image resolution. Local state per CLAUDE.md.

## Global constraints

Copied from CLAUDE.md and the ADRs. Every task inherits these.

- STOP and ask a human before: `terraform apply`, `terraform destroy`, any `terraform state` command, installing any dependency or provider, editing `.gitignore` or `.pre-commit-config.yaml`, creating files outside the repo layout, or modifying an existing file.
- Never commit `terraform.tfstate` or any tfvars file. Never write a secret, subscription ID, or tenant ID into any file.
- Never hardcode a marketplace publisher, offer, SKU, or version in `.tf` files. They come from `images.auto.tfvars`, written by `scripts/10-resolve-images.sh`.
- Never remove the `local` fallback from an AAA line in the router day-0 template.
- Every variable has a `description` and a `type`. Every resource carries the `project`, `owner`, and `expires` tags via `var.tags`.
- Gates for every `.tf` change: `terraform fmt -check`, `terraform validate`, `tfsec`. There is no unit test suite; the gates are the tests.
- Bash scripts use `set -euo pipefail`, quote every variable, functions under 40 lines.
- Skills to load before writing code in a task: `terraform-patterns`, `azure-cloud-architect`, `cloud-security`, `senior-secops`. Name them in the task's commit summary conversation.
- Commit messages carry no AI attribution of any kind.
- The azurerm 4.x provider needs a subscription ID. Supply it only through the shell: `export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)`. It never goes in a file.

---

### Task 1: .gitignore

The secret-protection net comes first, before any Terraform file exists.

**Files:**
- Create: `.gitignore`

**Interfaces:**
- Produces: ignore rules every later task relies on, especially `*.tfstate*` and `*.tfvars`.

- [ ] **Step 1: Get human approval**

`.gitignore` is on the CLAUDE.md approval list. Show the exact content below and wait for a yes.

- [ ] **Step 2: Write `.gitignore`**

```gitignore
# Terraform state and variable files hold the ISE admin password, the
# TACACS+ shared secret, and device credentials. Never commit them.
*.tfstate
*.tfstate.*
*.tfvars
crash.log
tfplan
.terraform/

# Python
.venv/
__pycache__/

# Ansible
*.retry

# macOS
.DS_Store
```

Note: `.terraform.lock.hcl` is deliberately not ignored. The provider lock file gets committed so rebuilds use identical provider builds.

- [ ] **Step 3: Verify the net catches what it must**

```bash
touch terraform.tfstate images.auto.tfvars
git status --porcelain | grep -E 'tfstate|tfvars'
rm terraform.tfstate images.auto.tfvars
```

Expected: the grep prints nothing. If either file shows as untracked, the pattern is wrong; fix before continuing.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "Ignore state, tfvars, and local tooling files"
```

---

### Task 2: Terraform skeleton and provider pinning

**Files:**
- Create: `terraform/versions.tf`
- Create: `terraform/providers.tf`
- Create: `terraform/variables.tf`
- Create: `terraform/locals.tf`
- Create: `terraform/terraform.tfvars.example`

**Interfaces:**
- Produces: root variables `location`, `owner`, `expires`, `name_prefix`, `ise_image`, `c8000v_image`, `ise_vm_size`, `c8000v_vm_size`, `ise_private_ip`, `dns_server`, and `local.common_tags`. Every later task consumes these names exactly.

- [ ] **Step 1: Get human approval for providers**

`terraform init` installs the azurerm, random, and tls providers. Installing a provider is on the approval list. Ask before running init, listing the three providers and their version constraints.

- [ ] **Step 2: Write `terraform/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
```

- [ ] **Step 3: Write `terraform/providers.tf`**

```hcl
# The subscription ID comes from ARM_SUBSCRIPTION_ID in the shell.
# It never appears in a file.
provider "azurerm" {
  features {}
}
```

- [ ] **Step 4: Write `terraform/variables.tf`**

```hcl
variable "location" {
  description = "Azure region for every lab resource (ADR 0001)"
  type        = string
  default     = "eastus2"
}

variable "owner" {
  description = "Value for the owner tag on every resource"
  type        = string
}

variable "expires" {
  description = "Value for the expires tag, an ISO date like 2026-09-30"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "tacacs-tue"
}

variable "ise_image" {
  description = "Marketplace image for Cisco ISE. Written by scripts/10-resolve-images.sh into images.auto.tfvars, never hardcoded."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "c8000v_image" {
  description = "Marketplace image for the Catalyst 8000V. Written by scripts/10-resolve-images.sh into images.auto.tfvars, never hardcoded."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "ise_vm_size" {
  description = "VM size for ISE. Default is the smallest size Cisco supports on Azure; verify against the ISE cloud guide in Task 6."
  type        = string
  default     = "Standard_D4s_v4"
}

variable "c8000v_vm_size" {
  description = "VM size for the C8000V. Verify against the C8000V Azure guide in Task 5."
  type        = string
  default     = "Standard_DS3_v2"
}

variable "ise_private_ip" {
  description = "Static private IP for ISE inside snet-mgmt. Static so the router day-0 config can reference it."
  type        = string
  default     = "10.80.0.68"
}

variable "dns_server" {
  description = "Azure's virtual DNS IP, the same constant in every VNet"
  type        = string
  default     = "168.63.129.16"
}
```

- [ ] **Step 5: Write `terraform/locals.tf`**

```hcl
locals {
  common_tags = {
    project = "tacacs-tuesday"
    owner   = var.owner
    expires = var.expires
  }
}
```

- [ ] **Step 6: Write `terraform/terraform.tfvars.example`**

```hcl
# Copy to terraform.tfvars (gitignored) and fill in.
owner   = "your-name"
expires = "2026-09-30"
```

- [ ] **Step 7: Run the gates**

```bash
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
```

Expected: init succeeds and writes `.terraform.lock.hcl`; fmt prints nothing; validate reports success. Validate will not complain about the unused image variables yet.

- [ ] **Step 8: Commit**

```bash
git add terraform/versions.tf terraform/providers.tf terraform/variables.tf terraform/locals.tf terraform/terraform.tfvars.example terraform/.terraform.lock.hcl
git commit -m "Add Terraform skeleton with pinned providers"
```

---

### Task 3: foundation module

Resource group, VNet, subnets, and the permissive-but-present NSGs from ADR 0002.

**Files:**
- Create: `terraform/modules/foundation/main.tf`
- Create: `terraform/modules/foundation/variables.tf`
- Create: `terraform/modules/foundation/outputs.tf`

**Interfaces:**
- Consumes: root values via module arguments (`name_prefix`, `location`, `tags`).
- Produces: outputs `resource_group_name`, `location`, `bastion_subnet_id`, `mgmt_subnet_id`, `nad_subnet_id`. Tasks 4, 5, 6, and 7 use these exact names.

- [ ] **Step 1: Write `terraform/modules/foundation/variables.tf`**

```hcl
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}

variable "vnet_cidr" {
  description = "Address space for the lab VNet (ADR 0001)"
  type        = string
  default     = "10.80.0.0/24"
}

variable "bastion_subnet_cidr" {
  description = "AzureBastionSubnet range"
  type        = string
  default     = "10.80.0.0/26"
}

variable "mgmt_subnet_cidr" {
  description = "snet-mgmt range, holds ISE"
  type        = string
  default     = "10.80.0.64/26"
}

variable "nad_subnet_cidr" {
  description = "snet-nad range, holds the C8000V"
  type        = string
  default     = "10.80.0.128/26"
}
```

- [ ] **Step 2: Write `terraform/modules/foundation/main.tf`**

```hcl
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
```

- [ ] **Step 3: Write `terraform/modules/foundation/outputs.tf`**

```hcl
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
```

- [ ] **Step 4: Run the gates**

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform/modules/foundation init -backend=false
terraform -chdir=terraform/modules/foundation validate
tfsec terraform/modules/foundation
```

Expected: all clean. If tfsec is not installed, stop and ask before installing it (dependency rule). If tfsec flags the VirtualNetwork-source rules, record the finding and the ADR 0002 justification in the commit message rather than tightening the rule.

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/foundation
git commit -m "Add foundation module: RG, VNet, subnets, permissive NSGs"
```

---

### Task 4: bastion module

**Files:**
- Create: `terraform/modules/bastion/main.tf`
- Create: `terraform/modules/bastion/variables.tf`
- Create: `terraform/modules/bastion/outputs.tf`

**Interfaces:**
- Consumes: `resource_group_name`, `location`, `bastion_subnet_id` from foundation.
- Produces: output `bastion_name`. Task 7 uses it to build tunnel commands.

- [ ] **Step 1: Write `terraform/modules/bastion/variables.tf`**

```hcl
variable "name" {
  description = "Bastion host name. CLAUDE.md tunnel commands assume bas-lab."
  type        = string
  default     = "bas-lab"
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "bastion_subnet_id" {
  description = "ID of AzureBastionSubnet"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}
```

- [ ] **Step 2: Write `terraform/modules/bastion/main.tf`**

```hcl
resource "azurerm_public_ip" "bastion" {
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Standard SKU with tunneling on. az network bastion tunnel does not work
# on Basic or Developer (ADR 0001).
resource "azurerm_bastion_host" "lab" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  tunneling_enabled   = true
  tags                = var.tags

  ip_configuration {
    name                 = "ipcfg"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}
```

- [ ] **Step 3: Write `terraform/modules/bastion/outputs.tf`**

```hcl
output "bastion_name" {
  description = "Bastion host name for az network bastion tunnel commands"
  value       = azurerm_bastion_host.lab.name
}
```

- [ ] **Step 4: Run the gates**

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform/modules/bastion init -backend=false
terraform -chdir=terraform/modules/bastion validate
tfsec terraform/modules/bastion
```

Expected: all clean.

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/bastion
git commit -m "Add bastion module: Standard SKU with native client tunneling"
```

---

### Task 5: c8000v module and router day-0 config

**Files:**
- Create: `terraform/modules/c8000v/main.tf`
- Create: `terraform/modules/c8000v/variables.tf`
- Create: `terraform/modules/c8000v/outputs.tf`
- Create: `terraform/modules/c8000v/templates/day0.cfg.tftpl`

**Interfaces:**
- Consumes: `resource_group_name`, `location`, `nad_subnet_id` from foundation; `admin_password`, `tacacs_secret`, `ise_ip`, `image` from the root.
- Produces: outputs `vm_id`, `private_ip`. Task 7 uses both.

- [ ] **Step 1: Verify the supported VM size and day-0 format**

Fetch Cisco's "Deploying Cisco Catalyst 8000V on Microsoft Azure" guide (search cisco.com for that exact title, current release). Confirm two things: that the default `Standard_DS3_v2` size is on the supported instance list, and that day-0 config is passed as custom data beginning with the line `Section: IOS configuration`. If either differs, update the variable default or the template header to match the guide before writing code.

- [ ] **Step 2: Write `terraform/modules/c8000v/variables.tf`**

```hcl
variable "name" {
  description = "VM and hostname for the router"
  type        = string
  default     = "c8kv-lab"
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_id" {
  description = "ID of snet-nad"
  type        = string
}

variable "vm_size" {
  description = "VM size, verified against the C8000V Azure guide"
  type        = string
}

variable "image" {
  description = "Marketplace image coordinates from images.auto.tfvars"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "admin_username" {
  description = "Local IOS user, the AAA fallback account"
  type        = string
  default     = "labadmin"
}

variable "admin_password" {
  description = "Password for the local IOS user"
  type        = string
  sensitive   = true
}

variable "tacacs_secret" {
  description = "TACACS+ shared secret, must match the ISE network device entry"
  type        = string
  sensitive   = true
}

variable "ise_ip" {
  description = "Private IP of the ISE VM, the TACACS+ server address"
  type        = string
}

variable "domain_name" {
  description = "IP domain name, required before SSH keys can generate"
  type        = string
  default     = "lab.internal"
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}
```

- [ ] **Step 3: Write `terraform/modules/c8000v/templates/day0.cfg.tftpl`**

The AAA lines all end in `local`. That fallback is a CLAUDE.md never-remove rule: with no console on an Azure VM, losing it means rebuild.

```text
Section: IOS configuration
hostname ${hostname}
ip domain name ${domain_name}
username ${admin_username} privilege 15 secret ${admin_password}
aaa new-model
tacacs server ISE
 address ipv4 ${ise_ip}
 key ${tacacs_secret}
aaa group server tacacs+ ISE-GROUP
 server name ISE
aaa authentication login default group ISE-GROUP local
aaa authorization exec default group ISE-GROUP local
aaa authorization commands 15 default group ISE-GROUP local
aaa accounting exec default start-stop group ISE-GROUP
aaa accounting commands 15 default start-stop group ISE-GROUP
ip ssh version 2
line vty 0 4
 transport input ssh
```

- [ ] **Step 4: Write `terraform/modules/c8000v/main.tf`**

```hcl
resource "azurerm_network_interface" "c8000v" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "c8000v" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.c8000v.id]
  tags                            = var.tags

  custom_data = base64encode(templatefile("${path.module}/templates/day0.cfg.tftpl", {
    hostname       = var.name
    domain_name    = var.domain_name
    admin_username = var.admin_username
    admin_password = var.admin_password
    ise_ip         = var.ise_ip
    tacacs_secret  = var.tacacs_secret
  }))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  plan {
    name      = var.image.sku
    product   = var.image.offer
    publisher = var.image.publisher
  }
}
```

- [ ] **Step 5: Write `terraform/modules/c8000v/outputs.tf`**

```hcl
output "vm_id" {
  description = "Resource ID, used by the Bastion tunnel command"
  value       = azurerm_linux_virtual_machine.c8000v.id
}

output "private_ip" {
  description = "Router management IP inside snet-nad"
  value       = azurerm_network_interface.c8000v.private_ip_address
}
```

- [ ] **Step 6: Run the gates**

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform/modules/c8000v init -backend=false
terraform -chdir=terraform/modules/c8000v validate
tfsec terraform/modules/c8000v
```

Expected: all clean. tfsec may warn about password authentication being enabled; that is how the C8000V marketplace image takes its initial credentials, so record the justification rather than changing it.

- [ ] **Step 7: Commit**

```bash
git add terraform/modules/c8000v
git commit -m "Add c8000v module with TACACS+ day-0 config and local fallback"
```

**Known risk, documented on purpose:** the day-0 AAA config points at ISE before ISE knows the router. Until the ISE side holds the network device entry, TACACS+ handshakes fail as connection errors and IOS falls back to `local`. The ISE provisioning script (future work, tracked in the roadmap) must run before anyone relies on TACACS+ logins.

---

### Task 6: ise module

**Files:**
- Create: `terraform/modules/ise/main.tf`
- Create: `terraform/modules/ise/variables.tf`
- Create: `terraform/modules/ise/outputs.tf`
- Create: `terraform/modules/ise/templates/userdata.txt.tftpl`

**Interfaces:**
- Consumes: `resource_group_name`, `location`, `mgmt_subnet_id` from foundation; `admin_password`, `image`, `private_ip`, `dns_server` from the root.
- Produces: outputs `vm_id`, `private_ip`, `ssh_private_key` (sensitive). Task 7 uses all three.

- [ ] **Step 1: Verify user-data keys, VM size, and disk floor**

Fetch Cisco's "Cisco ISE on Cloud" guide, Azure chapter (search cisco.com for "ISE on Azure Cloud Services", current release). Confirm: the supported instance list includes `Standard_D4s_v4`; the minimum OS disk size (the template below assumes 300 GB); the admin username Azure enforces (the template below assumes `iseadmin` with SSH key auth); and the exact user-data key names. The keys below are the documented set as of ISE 3.x; if the guide differs, the guide wins.

- [ ] **Step 2: Write `terraform/modules/ise/templates/userdata.txt.tftpl`**

```text
hostname=${hostname}
primarynameserver=${dns_server}
dnsdomain=${domain_name}
ntpserver=${ntp_server}
timezone=UTC
password=${admin_password}
ersapi=yes
openapi=yes
pxGrid=no
pxgrid_cloud=no
```

`ersapi=yes` and `openapi=yes` matter: the MCP suite's ISE server talks ERS through the API gateway on 443 (ADR 0002), and both APIs ship disabled by default.

- [ ] **Step 3: Write `terraform/modules/ise/variables.tf`**

```hcl
variable "name" {
  description = "VM and hostname for ISE"
  type        = string
  default     = "ise-lab"
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_id" {
  description = "ID of snet-mgmt"
  type        = string
}

variable "private_ip" {
  description = "Static private IP, referenced by the router day-0 config"
  type        = string
}

variable "vm_size" {
  description = "VM size, verified against the ISE cloud guide"
  type        = string
}

variable "os_disk_gb" {
  description = "OS disk size. ISE on Azure needs at least 300 GB; verify in Task 6 Step 1."
  type        = number
  default     = 300
}

variable "image" {
  description = "Marketplace image coordinates from images.auto.tfvars"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "admin_username" {
  description = "CLI admin user. Cisco's Azure image expects iseadmin."
  type        = string
  default     = "iseadmin"
}

variable "admin_password" {
  description = "ISE GUI admin password, set through user data"
  type        = string
  sensitive   = true
}

variable "dns_server" {
  description = "DNS server handed to ISE"
  type        = string
}

variable "ntp_server" {
  description = "NTP server handed to ISE"
  type        = string
  default     = "time.windows.com"
}

variable "domain_name" {
  description = "DNS domain for the ISE node"
  type        = string
  default     = "lab.internal"
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
}
```

- [ ] **Step 4: Write `terraform/modules/ise/main.tf`**

```hcl
resource "azurerm_network_interface" "ise" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "ipcfg"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip
  }
}

# Cisco's Azure image authenticates the CLI user with an SSH key, not a
# password. The key is generated here so a rebuild never depends on state
# outside Terraform (ADR 0004).
resource "tls_private_key" "ise" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "ise" {
  name                  = var.name
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.ise.id]
  tags                  = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ise.public_key_openssh
  }

  user_data = base64encode(templatefile("${path.module}/templates/userdata.txt.tftpl", {
    hostname       = var.name
    dns_server     = var.dns_server
    domain_name    = var.domain_name
    ntp_server     = var.ntp_server
    admin_password = var.admin_password
  }))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.os_disk_gb
  }

  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  plan {
    name      = var.image.sku
    product   = var.image.offer
    publisher = var.image.publisher
  }
}
```

- [ ] **Step 5: Write `terraform/modules/ise/outputs.tf`**

```hcl
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
```

- [ ] **Step 6: Run the gates**

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform/modules/ise init -backend=false
terraform -chdir=terraform/modules/ise validate
tfsec terraform/modules/ise
```

Expected: all clean.

- [ ] **Step 7: Commit**

```bash
git add terraform/modules/ise
git commit -m "Add ise module with day-0 user data and generated SSH key"
```

---

### Task 7: Root wiring, secrets, and outputs

**Files:**
- Create: `terraform/main.tf`
- Create: `terraform/outputs.tf`

**Interfaces:**
- Consumes: every module output named in Tasks 3 through 6, plus the root variables from Task 2.
- Produces: the complete deployable root module and the outputs the runbooks will copy from.

- [ ] **Step 1: Write `terraform/main.tf`**

Character sets are deliberate: ISE rejects many specials (the safe set here is `#_-`), and plain alphanumerics keep IOS and TACACS+ quoting painless.

```hcl
resource "random_password" "ise_admin" {
  length           = 16
  special          = true
  override_special = "#_-"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
}

resource "random_password" "c8000v_admin" {
  length  = 16
  special = false
}

resource "random_password" "tacacs_secret" {
  length  = 24
  special = false
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

module "ise" {
  source = "./modules/ise"

  resource_group_name = module.foundation.resource_group_name
  location            = module.foundation.location
  subnet_id           = module.foundation.mgmt_subnet_id
  private_ip          = var.ise_private_ip
  vm_size             = var.ise_vm_size
  image               = var.ise_image
  admin_password      = random_password.ise_admin.result
  dns_server          = var.dns_server
  tags                = local.common_tags
}

module "c8000v" {
  source = "./modules/c8000v"

  resource_group_name = module.foundation.resource_group_name
  location            = module.foundation.location
  subnet_id           = module.foundation.nad_subnet_id
  vm_size             = var.c8000v_vm_size
  image               = var.c8000v_image
  admin_password      = random_password.c8000v_admin.result
  tacacs_secret       = random_password.tacacs_secret.result
  ise_ip              = var.ise_private_ip
  tags                = local.common_tags
}
```

- [ ] **Step 2: Write `terraform/outputs.tf`**

```hcl
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
```

- [ ] **Step 3: Run the gates**

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
tfsec terraform
```

Expected: all clean. Full `terraform plan` waits for Task 8, which produces the image tfvars that plan needs.

- [ ] **Step 4: Commit**

```bash
git add terraform/main.tf terraform/outputs.tf
git commit -m "Wire root module: secrets, module composition, tunnel outputs"
```

---

### Task 8: Image resolution script and first plan

**Files:**
- Create: `scripts/10-resolve-images.sh`

**Interfaces:**
- Consumes: the `ise_image` and `c8000v_image` variable shapes from Task 2.
- Produces: `terraform/images.auto.tfvars` (gitignored), which makes `terraform plan` possible.

- [ ] **Step 1: Write `scripts/10-resolve-images.sh`**

```bash
#!/usr/bin/env bash
# Resolve the current Cisco ISE and Catalyst 8000V marketplace images,
# accept their terms, and pin exact versions into images.auto.tfvars.
# Re-running is safe. Re-run on purpose to bump an image version.
set -euo pipefail

LOCATION="${LOCATION:-eastus2}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_FILE="${REPO_ROOT}/terraform/images.auto.tfvars"

# Find the publisher named exactly "cisco" rather than trusting a blog post.
find_publisher() {
  az vm image list-publishers --location "${LOCATION}" \
    --query "[?name=='cisco'].name" -o tsv
}

# Newest offer matching a pattern, e.g. "ise" or "c8000v".
find_offer() {
  local publisher="$1" pattern="$2"
  az vm image list-offers --location "${LOCATION}" --publisher "${publisher}" \
    --query "[?contains(name, '${pattern}')].name" -o tsv | sort | tail -n 1
}

# Newest SKU for an offer. BYOL SKUs are preferred when present.
find_sku() {
  local publisher="$1" offer="$2"
  local skus
  skus="$(az vm image list-skus --location "${LOCATION}" \
    --publisher "${publisher}" --offer "${offer}" --query "[].name" -o tsv)"
  if echo "${skus}" | grep -q 'byol'; then
    echo "${skus}" | grep 'byol' | sort | tail -n 1
  else
    echo "${skus}" | sort | tail -n 1
  fi
}

# Newest version for a SKU, pinned exactly.
find_version() {
  local publisher="$1" offer="$2" sku="$3"
  az vm image list --location "${LOCATION}" --publisher "${publisher}" \
    --offer "${offer}" --sku "${sku}" --all \
    --query "sort_by([], &version)[-1].version" -o tsv
}

accept_terms() {
  local publisher="$1" offer="$2" sku="$3"
  az vm image terms accept --publisher "${publisher}" --offer "${offer}" \
    --plan "${sku}" --only-show-errors > /dev/null
}

main() {
  local publisher
  publisher="$(find_publisher)"
  if [[ -z "${publisher}" ]]; then
    echo "No 'cisco' publisher found in ${LOCATION}" >&2
    exit 1
  fi

  local ise_offer c8k_offer
  ise_offer="$(find_offer "${publisher}" "ise")"
  c8k_offer="$(find_offer "${publisher}" "c8000v")"

  local ise_sku c8k_sku
  ise_sku="$(find_sku "${publisher}" "${ise_offer}")"
  c8k_sku="$(find_sku "${publisher}" "${c8k_offer}")"

  local ise_version c8k_version
  ise_version="$(find_version "${publisher}" "${ise_offer}" "${ise_sku}")"
  c8k_version="$(find_version "${publisher}" "${c8k_offer}" "${c8k_sku}")"

  echo "ISE:    ${publisher} / ${ise_offer} / ${ise_sku} / ${ise_version}"
  echo "C8000V: ${publisher} / ${c8k_offer} / ${c8k_sku} / ${c8k_version}"

  accept_terms "${publisher}" "${ise_offer}" "${ise_sku}"
  accept_terms "${publisher}" "${c8k_offer}" "${c8k_sku}"

  cat > "${OUT_FILE}" <<EOF
# Written by scripts/10-resolve-images.sh. Do not edit by hand.
ise_image = {
  publisher = "${publisher}"
  offer     = "${ise_offer}"
  sku       = "${ise_sku}"
  version   = "${ise_version}"
}
c8000v_image = {
  publisher = "${publisher}"
  offer     = "${c8k_offer}"
  sku       = "${c8k_sku}"
  version   = "${c8k_version}"
}
EOF

  echo "Wrote ${OUT_FILE}"
}

main "$@"
```

- [ ] **Step 2: Syntax-check and run**

```bash
bash -n scripts/10-resolve-images.sh
chmod +x scripts/10-resolve-images.sh
az account show > /dev/null || az login
scripts/10-resolve-images.sh
```

Expected: the script prints both image coordinate lines and writes `terraform/images.auto.tfvars`. Sanity-check the printed offers look like ISE and C8000V products. If the offer grep matches nothing, list the publisher's offers manually with `az vm image list-offers --location eastus2 --publisher cisco -o table` and adjust the pattern.

- [ ] **Step 3: Confirm the tfvars file is ignored**

```bash
git status --porcelain | grep tfvars
```

Expected: nothing. Only `terraform.tfvars.example` is ever committed.

- [ ] **Step 4: First full plan**

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in `owner` and `expires`. Then:

```bash
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform -chdir=terraform plan -out=tfplan
```

Expected: a plan that creates roughly 15 resources and destroys nothing. Read every line. Common failures: quota (fix: request D-family vCPU quota in eastus2 or change region), and terms not accepted (fix: re-run the script and read its errors).

- [ ] **Step 5: Commit**

```bash
git add scripts/10-resolve-images.sh
git commit -m "Add marketplace image resolution script"
```

---

### Task 9: pre-commit and secret scanning

**Files:**
- Create: `.pre-commit-config.yaml`
- Create: `.gitleaks.toml`

**Interfaces:**
- Produces: the `pre-commit run --all-files` gate that CLAUDE.md's definition of done requires.

- [ ] **Step 1: Get human approval**

Both files are on the CLAUDE.md approval list, and installing `pre-commit` itself is a dependency install. Show the content below and the install command, and wait for a yes.

- [ ] **Step 2: Write `.pre-commit-config.yaml`**

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
      - id: terraform_validate

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
```

- [ ] **Step 3: Write `.gitleaks.toml`**

```toml
# Extends the default gitleaks rules. The default ruleset already covers
# generic secrets; this file exists so future allowlist entries have a home
# and every allowlist decision is visible in git history.
[extend]
useDefault = true
```

- [ ] **Step 4: Install and run**

```bash
pip install pre-commit
pre-commit run --all-files
```

Expected: all hooks pass. If terraform_validate fails here but passed in Task 7, the hook is running in the wrong directory; check the hook's default behavior against the `terraform/` layout before changing any code.

- [ ] **Step 5: Commit**

```bash
git add .pre-commit-config.yaml .gitleaks.toml
git commit -m "Add pre-commit gates: fmt, validate, whitespace, gitleaks"
```

---

### Task 10: Plan review and apply handoff

**Files:** none. This task ends in a human decision, not a commit.

- [ ] **Step 1: Regenerate a fresh plan**

```bash
terraform -chdir=terraform plan -out=tfplan
```

- [ ] **Step 2: Present the plan summary to the human**

Report: resource count by type, the two VM sizes and image versions being deployed, estimated hourly cost (about $0.75/hour per ADR 0004), and any warnings. Then stop. `terraform apply` requires explicit human approval per CLAUDE.md, and the first apply doubles as the first rebuild rehearsal.

- [ ] **Step 3: After an approved apply, verify the lab end to end**

```bash
terraform -chdir=terraform output bastion_tunnel_commands
# In separate terminals, start both tunnels, then:
curl -sk https://localhost:8443 -o /dev/null -w '%{http_code}\n'   # expect 200 or 302 once ISE settles (30-45 min)
ssh -p 2222 labadmin@localhost 'show version | include uptime'      # expect router uptime line
```

ISE is not up until the GUI answers; give it the full 45 minutes before declaring failure.

---

## Roadmap (not in this plan)

Tracked here so they are not forgotten; each needs its own plan.

- ISE application provisioning script: network device entry, shell profiles, command sets, policy sets via the ERS/OpenAPI after each apply. Required by ADR 0004 before the demos can run.
- Ansible inventory and playbooks `01-facts` through `05-rollback`.
- `scripts/99-destroy.sh` teardown wrapper.
- Verify the ios-xe MCP server accepts a host:port device target through the local 2222 tunnel.
- GitHub Pages site with the full setup walkthrough.

## Self-review notes

Checked against ADRs 0001 through 0005: topology, region, and Bastion SKU (Task 3, 4), NSG posture and no-NSG-on-Bastion-subnet (Task 3), generated secrets and gitignored tfvars (Tasks 1, 7, 8), destroy-between-sessions consequences (day-0 completeness in Tasks 5, 6; pinned images in Task 8), and script-resolved images (Task 8). Interface names were cross-checked: every module output consumed in Task 7 is defined verbatim in Tasks 3 through 6.
