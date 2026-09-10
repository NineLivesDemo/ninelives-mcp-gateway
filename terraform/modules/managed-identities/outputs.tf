output "identities" {
  description = "Managed identity resource and principal identifiers."
  value = {
    for identity_key, identity in module.identity :
    identity_key => {
      resource_id  = identity.resource_id
      client_id    = identity.client_id
      principal_id = identity.principal_id
    }
  }
}
