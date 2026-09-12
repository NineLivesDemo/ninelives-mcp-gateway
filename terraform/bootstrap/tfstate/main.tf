resource "random_string" "storage_account_suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  storage_account_name = "${var.storage_account_name_prefix}${random_string.storage_account_suffix.result}"
  state_writer_principal_ids = setunion(
    toset([data.azurerm_client_config.current.object_id]),
    var.additional_state_writer_principal_ids,
  )
  blob_properties = {
    versioning_enabled = true
    delete_retention_policy = {
      enabled                = true
      days                   = var.blob_delete_retention_days
      allow_permanent_delete = false
    }
    container_delete_retention_policy = {
      enabled                = true
      days                   = var.blob_delete_retention_days
      allow_permanent_delete = false
    }
  }
  network_rules = {
    bypass         = ["None"]
    default_action = "Allow"
  }
}

module "state_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  enable_telemetry = false
  location         = var.location
  name             = var.resource_group_name
  tags             = var.tags
}

module "state_storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  account_kind                    = "StorageV2"
  account_sku_name                = "Standard_ZRS"
  allow_nested_items_to_be_public = false
  blob_properties                 = local.blob_properties
  containers = {
    tfstate = {
      name          = var.container_name
      public_access = "None"
      role_assignments = {
        for principal_id in local.state_writer_principal_ids : principal_id => {
          role_definition_id_or_name = "Storage Blob Data Contributor"
          principal_id               = principal_id
          description                = "Read, write, and lock Terraform state blobs."
        }
      }
    }
  }
  cross_tenant_replication_enabled = false
  default_to_oauth_authentication  = true
  enable_telemetry                 = false
  https_traffic_only_enabled       = true
  location                         = var.location
  min_tls_version                  = "TLS1_2"
  name                             = local.storage_account_name
  network_rules                    = local.network_rules
  parent_id                        = module.state_resource_group.resource_id
  public_network_access_enabled    = true
  shared_access_key_enabled        = false
  tags                             = var.tags
}
