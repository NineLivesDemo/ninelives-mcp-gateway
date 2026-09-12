# Ansible role and Molecule testing

The `platform_baseline` role is the first deliberately small convergence unit, exercised through a Molecule-managed Ansible playbook. Molecule is the testing framework for our roles, playbooks, and future collections.
It installs only baseline packages and writes a managed marker. The same framework will test larger playbook workflows and collection interfaces as they are added. Molecule owns
the isolated Docker test instance; it does not target or destroy Azure VMs.

Install Ansible Galaxy dependencies and run the isolated scenario from this directory:

```bash
uv run ansible-galaxy collection install -r ansible/requirements.yml
cd ansible
uv run molecule test -s default
uv run molecule test -s semaphore
```

The `semaphore` scenario renders the Compose template with gathered VM facts and verifies that the listener uses the VM private address rather than the local Bastion tunnel address. It does not start Docker services or contact Vault.

The separate `ansible/playbooks/connectivity-check.yml` remains the private Azure
runner connectivity proof. It is not a Molecule scenario because it targets
the durable platform environment.
