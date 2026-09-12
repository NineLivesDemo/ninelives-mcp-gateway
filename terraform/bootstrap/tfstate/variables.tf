variable "location" {
  description = "Azure region for the Terraform state backend."
  type        = string
}

variable "resource_group_name" {
  description = "Dedicated resource group for Terraform state infrastructure."
  type        = string
}

variable "storage_account_name_prefix" {
  description = "Lowercase alphanumeric prefix for the globally unique state storage account name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,18}$", var.storage_account_name_prefix))
    error_message = "storage_account_name_prefix must contain 3 to 18 lowercase alphanumeric characters."
  }
}

variable "container_name" {
  description = "Private Blob container that stores Terraform state."
  type        = string
  default     = "tfstate"
}

variable "blob_delete_retention_days" {
  description = "Number of days to retain deleted state blobs and containers."
  type        = number
  default     = 30

  validation {
    condition     = var.blob_delete_retention_days >= 1 && var.blob_delete_retention_days <= 365
    error_message = "blob_delete_retention_days must be between 1 and 365."
  }
}

variable "additional_state_writer_principal_ids" {
  description = "Additional Microsoft Entra principal object IDs allowed to read, write, and lock state blobs."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to Terraform state resources."
  type        = map(string)
  default     = {}
}
