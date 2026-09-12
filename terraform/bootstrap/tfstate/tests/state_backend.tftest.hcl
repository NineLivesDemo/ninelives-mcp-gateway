mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "modtm" {}
mock_provider "random" {}
mock_provider "time" {}

run "creates_a_private_entra_only_state_backend" {
  command = plan

  variables {
    location                    = "westus3"
    resource_group_name         = "rg-platform-tfstate"
    storage_account_name_prefix = "stplatformtf"
  }

  assert {
    condition     = output.state_container_name == "tfstate"
    error_message = "The state backend must use the tfstate container."
  }

  assert {
    condition     = output.state_backend_security.container_public_access == "None"
    error_message = "The state container must not allow anonymous access."
  }

  assert {
    condition     = output.state_backend_security.shared_access_key_enabled == false
    error_message = "Shared key access must remain disabled."
  }

  assert {
    condition     = output.state_backend_security.versioning_enabled == true
    error_message = "Blob versioning must remain enabled."
  }

  assert {
    condition     = output.state_backend_security.blob_delete_retention_days == 30
    error_message = "Deleted state blobs must retain the configured recovery window."
  }
}
