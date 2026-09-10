variable "location" {
  description = "Azure region for the ingress/platform-services VNet."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the ingress/platform-services resource group."
  type        = string
}

variable "name" {
  description = "Name of the ingress/platform-services VNet."
  type        = string
}

variable "address_space" {
  description = "CIDR ranges assigned to the ingress/platform-services VNet."
  type        = list(string)
}

variable "subnets" {
  description = "Subnets created in the ingress/platform-services VNet."
  type = map(object({
    name             = string
    address_prefixes = list(string)
  }))
}

variable "hub_virtual_network_id" {
  description = "Resource ID of the platform connectivity hub VNet."
  type        = string
}

variable "tags" {
  description = "Tags applied to the ingress/platform-services VNet."
  type        = map(string)
  default     = {}
}
