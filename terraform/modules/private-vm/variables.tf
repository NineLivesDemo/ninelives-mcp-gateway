variable "location" {
  description = "Azure region for the VM."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name that owns the VM."
  type        = string
}

variable "name" {
  description = "Private VM name."
  type        = string
}

variable "subnet_resource_id" {
  description = "Private subnet resource ID for the VM NIC."
  type        = string
}

variable "user_assigned_identity_ids" {
  description = "User-assigned managed identity resource IDs attached to the VM."
  type        = set(string)
  default     = []
}

variable "ssh_public_key" {
  description = "SSH public key for private operator access through Bastion."
  type        = string
  sensitive   = true
}

variable "admin_username" {
  description = "Linux administrator username."
  type        = string
  default     = "azureuser"
}

variable "sku_size" {
  description = "Azure VM SKU."
  type        = string
  default     = "Standard_D2ds_v5"
}

variable "zone" {
  description = "Availability zone for the VM."
  type        = string
  default     = "1"
}

variable "tags" {
  description = "Tags applied to the VM and supporting resources."
  type        = map(string)
  default     = {}
}
