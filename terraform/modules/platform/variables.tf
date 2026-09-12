variable "location" {
  description = "Azure region for the platform landing zone."
  type        = string
}

variable "hub_resource_group_id" {
  description = "Resource ID of the platform connectivity hub resource group."
  type        = string
}

variable "hub_name" {
  description = "Name of the platform connectivity hub VNet."
  type        = string
}

variable "hub_address_space" {
  description = "CIDR ranges assigned to the platform connectivity hub."
  type        = list(string)
}

variable "hub_subnets" {
  description = "Subnets created in the platform connectivity hub."
  type = map(object({
    name             = string
    address_prefixes = list(string)
  }))
}

variable "enable_bastion_tunneling" {
  description = "Whether Azure Bastion native-client tunneling is enabled."
  type        = bool
  default     = false
}

variable "ingress_resource_group_id" {
  description = "Resource ID of the ingress/platform-services resource group."
  type        = string
}

variable "ingress_vnet_name" {
  description = "Name of the private ingress/platform-services VNet."
  type        = string
}

variable "ingress_address_space" {
  description = "CIDR ranges assigned to the ingress/platform-services VNet."
  type        = list(string)
}

variable "ingress_subnets" {
  description = "Subnets created in the ingress/platform-services VNet."
  type = map(object({
    name                   = string
    address_prefixes       = list(string)
    nat_gateway            = optional(object({ id = string }))
    network_security_group = optional(object({ id = string }))
    route_table            = optional(object({ id = string }))
  }))
}

variable "tags" {
  description = "Tags applied to platform landing-zone resources."
  type        = map(string)
  default     = {}
}
