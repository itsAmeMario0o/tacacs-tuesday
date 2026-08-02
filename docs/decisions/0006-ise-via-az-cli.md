# ADR 0006: Provision ISE with the az CLI, not Terraform

## Status

Accepted, 2026-08-02.

## Context

Getting ISE to start on Azure took many small iterations: VM size, NTP,
DNS, and the day-0 key names all had to be right before the application
would come up. Terraform made each iteration slow and painful. A single
ISE rebuild takes 20 or more minutes just to learn whether the day-0 was
accepted, then another 30 to 45 for the app to build. Worse, when ISE
provisioning failed, Azure marked the VM failed and Terraform left it out
of state, so every retry needed manual reconciliation before the next
apply would run.

Terraform is the right tool for the network, Bastion, and the router,
which are stable and build cleanly. ISE is the one component still being
figured out, and it needs fast, throwaway iteration.

## Decision

Terraform builds the network, Bastion, and the C8000V. ISE is deployed
separately with `scripts/90-ise-deploy.sh` using the az CLI, into the
VNet Terraform creates.

- The ISE module and its outputs are commented out in Terraform, not
  deleted, so the working code is one uncomment away when ISE is ready to
  return.
- `random_password.ise_admin` stays in Terraform. The admin password is
  still generated and stored in one place, and the script reads it with
  `terraform output -raw ise_admin_password`.
- The script defaults to `Standard_D8s_v4`, the smallest instance Cisco
  supports for ISE on Azure, and to a real NTP server by IP.

## Consequences

- Fast iteration on ISE. Change one field, redeploy, no Terraform cycle
  and no state reconciliation.
- ISE is not in Terraform state, so its IP, VM ID, and SSH key are not
  Terraform outputs. The script prints what it creates.
- `terraform destroy` does not remove ISE. Delete the ISE VM, its NIC,
  and its disk first, or the VNet will not delete while the ISE NIC is
  still attached to the subnet.
- This is a lab convenience, not a production pattern. Once ISE's
  requirements are pinned down and it boots reliably, it can move back
  into Terraform by uncommenting the module.
- It narrows ADR 0004 for ISE specifically. The "complete day-0 in
  Terraform" goal still holds for everything else; ISE's day-0 now lives
  in the script.

## Options considered

Keep ISE in Terraform with a longer provisioner timeout. Rejected. It is
still 20 or more minutes per iteration, and a failed provision still
drops the VM out of state, which is the exact problem that slowed
bring-up.

Build ISE by hand and import it back into Terraform after each deploy.
Rejected. That is an extra step every session for a lab, and the import
has to be redone on every rebuild.
