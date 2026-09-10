variable "location" {
  description = "Azure region for the platform connectivity hub."
  type        = string
}

variable "hub_resource_group_id" {
  description = "Resource ID of the resource group that owns the connectivity hub."
  type        = string
}

variable "hub_name" {
  description = "Name of the platform connectivity hub VNet."
  type        = string
}

variable "hub_address_space" {
  description = "CIDR ranges assigned to the platform connectivity hub VNet."
  type        = list(string)
}

variable "hub_subnets" {
  description = "Subnets owned by the platform connectivity hub."
  type = map(object({
    name             = string
    address_prefixes = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to platform connectivity resources."
  type        = map(string)
  default     = {}
}

variable "enable_bastion" {
  description = "Whether to create Azure Bastion in the connectivity hub."
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Whether to create the centralized NAT Gateway capability."
  type        = bool
  default     = true
}

variable "enable_firewall" {
  description = "Whether to create Azure Firewall in the connectivity hub."
  type        = bool
  default     = false
}

variable "enable_private_dns_zones" {
  description = "Whether the connectivity pattern owns shared Private Link DNS zones."
  type        = bool
  default     = false
}
