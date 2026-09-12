output "state_resource_group_name" {
  description = "Terraform state resource group name."
  value       = module.state_resource_group.name
}

output "state_storage_account_name" {
  description = "Terraform state Storage account name."
  value       = module.state_storage.name
}

output "state_container_name" {
  description = "Private Blob container that stores Terraform state."
  value       = module.state_storage.containers["tfstate"].name
}

output "state_container_resource_id" {
  description = "Resource ID for the private Terraform state container."
  value       = module.state_storage.containers["tfstate"].id
}

output "state_blob_hostname" {
  description = "Blob data-plane hostname for Terraform backend diagnostics."
  value       = module.state_storage.fqdn["blob"]
}

output "state_backend_security" {
  description = "Non-secret state-backend security contract."
  value = {
    blob_delete_retention_days    = var.blob_delete_retention_days
    container_public_access       = "None"
    public_network_access_enabled = true
    shared_access_key_enabled     = false
    versioning_enabled            = local.blob_properties.versioning_enabled
  }
}
