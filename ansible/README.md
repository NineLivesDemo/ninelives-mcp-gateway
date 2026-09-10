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
