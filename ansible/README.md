# Ansible platform configuration

This directory contains the first Ansible execution slice for the private Azure
platform. Terraform remains the infrastructure authority; Ansible consumes the
deliberately shaped `ansible_hosts` Terraform output and owns VM-local
configuration.

## Generate inventory

From the repository root:

```bash
./scripts/generate-ansible-inventory.sh
```

The generated inventory is local-only and contains private IP addresses. It
does not contain credentials, keys, Vault tokens, or Terraform state.

## Run the connectivity check

The runner must have an approved SSH identity that is authorized on the target
VMs before this playbook is run from Semaphore:

```bash
ansible-playbook ansible/playbooks/connectivity-check.yml
```

The current Terraform VM contract exposes `azureuser` and private addresses
only. Do not copy an operator's private SSH key to the automation VM. Establish
a dedicated runner key or another approved credential-delivery mechanism before
enabling this job in Semaphore.

## Semaphore bootstrap

The Semaphore control plane is bootstrapped once through Azure Bastion, then
Semaphore owns normal Ansible execution. The bootstrap implementation is the
versioned `playbooks/bootstrap-semaphore.yml` playbook and `roles/semaphore/`;
there is no repository shell wrapper.

1. In one terminal, open a supported Azure Bastion native-client tunnel from local port `2222` to SSH port `22` on `vm-automation-platform`.
2. Copy `inventory/bootstrap.ini.example` to the ignored `inventory/bootstrap.ini` and keep its loopback tunnel settings.
3. Add the automation VM SSH host key to the operator's `known_hosts` through a trusted, out-of-band verification path. Do not use trust-on-first-use host scanning.
4. Source the approved Vault bootstrap environment files without printing their values.
5. Run the playbook directly, passing the operator key with `--private-key`:

```bash
cd ansible
uv run ansible-playbook \
  -i inventory/bootstrap.ini \
  --private-key "$HOME/.ssh/id_ed25519" \
  playbooks/bootstrap-semaphore.yml
```

The playbook gathers facts from the existing VM and binds Semaphore to its actual private address, never the local tunnel address. It retrieves runtime values from Vault, renders the Compose files with restrictive permissions, starts the pinned Compose stack, and waits for `/api/ping` to return `pong`.

After bootstrap, use a second Bastion tunnel to VM port `3000` for operator UI access. Normal service-VM jobs remain disabled until dynamic inventory and Vault-signed SSH connectivity pass their separate acceptance checks.
