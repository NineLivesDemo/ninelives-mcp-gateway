variable "domain_name" {
  description = "Private DNS zone domain name."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the resource group that owns the private DNS zone."
  type        = string
}

variable "virtual_network_ids" {
  description = "Virtual network IDs to link to the private DNS zone."
  type        = map(string)
}

variable "tags" {
  description = "Tags applied to the private DNS zone."
  type        = map(string)
  default     = {}
}
