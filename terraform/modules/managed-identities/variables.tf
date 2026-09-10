variable "location" {
  description = "Azure region for the managed identities."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name that owns the managed identities."
  type        = string
}

variable "identities" {
  description = "Named managed identities and their explicitly scoped role assignments."
  type = map(object({
    name = string
    role_assignments = optional(map(object({
      role_definition_id_or_name = string
      scope                      = string
      description                = optional(string)
    })), {})
  }))
}

variable "tags" {
  description = "Tags applied to managed identities."
  type        = map(string)
  default     = {}
}
