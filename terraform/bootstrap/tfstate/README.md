# Terraform State Bootstrap

This root creates the Azure Blob backend used by Terraform environment roots. It intentionally starts with local state because a Terraform root cannot create the backend that it needs before initialization.

## Security model

- The Blob container is private and anonymous access is disabled.
- Azure Storage account keys are disabled; state access uses Microsoft Entra ID data-plane RBAC.
- The bootstrap operator is automatically granted `Storage Blob Data Contributor` on the state container. Add future CI or recovery principals through `additional_state_writer_principal_ids`.
- Azure Storage provides Microsoft-managed encryption at rest. Customer-managed keys are intentionally out of scope.
- The Storage endpoint is temporarily public for operator-driven Terraform. This does not make state public: access still requires an authorized Entra principal.
- Blob versioning plus blob and container soft delete provide recovery from accidental deletion or overwrite.

## Bootstrap

Authenticate with Azure CLI using the operator identity that can create resource groups, storage accounts, and role assignments.

```bash
az login
az account set --subscription <subscription-id>
cp terraform/bootstrap/tfstate/terraform.tfvars.example terraform/bootstrap/tfstate/terraform.tfvars
terraform -chdir=terraform/bootstrap/tfstate init -backend=false
terraform -chdir=terraform/bootstrap/tfstate apply
```

After the Storage account and container exist, create an ignored `backend.hcl` with the bootstrap state key `bootstrap/tfstate.tfstate`, then run `terraform init -migrate-state -backend-config=<absolute-path-to-backend.hcl>`.

Do not commit `terraform.tfvars`, local state, plans, backend configuration, or `.terraform/` directories.

## Migrate an environment root

1. Record the active local workspace and create an encrypted, access-restricted backup of the current local state outside the repository.
2. Copy `terraform/env/dev/backend.hcl.example` to ignored `terraform/env/dev/backend.hcl`.
3. Set `storage_account_name` to the `state_storage_account_name` bootstrap output.
4. Run `terraform -chdir=terraform/env/dev init -migrate-state -backend-config=backend.hcl`.
5. Run a fresh reviewed plan. Keep the encrypted local backup until the remote state, Blob locking, and recovery procedure have been validated.

Terraform backend coordinates are non-secret. Do not place credentials, access keys, SAS tokens, or client secrets in `backend.hcl`; Terraform uses the Azure CLI Entra session for this operator-driven workflow.

## Future hardening

When a stable operator egress allowlist or private network path is available, restrict the Storage account network boundary without changing the state container, Entra RBAC, or backend key model.
