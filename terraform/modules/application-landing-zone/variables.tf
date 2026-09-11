variable "location" {
  description = "Azure region for the application landing zone."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the application landing-zone resource group."
  type        = string
}

variable "vnet_name" {
  description = "Name of the private application landing-zone VNet."
  type        = string
}

variable "address_space" {
  description = "CIDR ranges assigned to the private application landing-zone VNet."
  type        = list(string)
}

variable "subnets" {
  description = "Private subnets for the application landing-zone workload."
  type = map(object({
    name                   = string
    address_prefixes       = list(string)
    network_security_group = optional(object({ id = string }))
    route_table            = optional(object({ id = string }))
  }))
}

variable "hub_virtual_network_id" {
  description = "Resource ID of the platform connectivity hub VNet."
  type        = string
}

variable "ingress_virtual_network_id" {
  description = "Resource ID of the private ingress/platform-services VNet."
  type        = string
}

variable "tags" {
  description = "Tags applied to application landing-zone resources."
  type        = map(string)
  default     = {}
}
