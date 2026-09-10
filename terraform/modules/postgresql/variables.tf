variable "location" {
  description = "Azure region for PostgreSQL."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name that owns PostgreSQL."
  type        = string
}

variable "name" {
  description = "PostgreSQL Flexible Server name."
  type        = string
}

variable "administrator_login" {
  description = "PostgreSQL administrator login name."
  type        = string
}

variable "administrator_password" {
  description = "Ephemeral PostgreSQL administrator password."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "administrator_password_version" {
  description = "Change this value to rotate the write-only administrator password."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Dedicated private endpoint subnet resource ID."
  type        = string
}

variable "private_dns_zone_id" {
  description = "PostgreSQL private DNS zone resource ID."
  type        = string
}

variable "tags" {
  description = "Tags applied to PostgreSQL resources."
  type        = map(string)
  default     = {}
}
