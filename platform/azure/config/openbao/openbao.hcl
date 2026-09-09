ui = true
disable_mlock = true

api_addr = "https://openbao.platform.internal:8200"
cluster_addr = "https://127.0.0.1:8201"

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "127.0.0.1:8201"
  tls_cert_file   = "/openbao/tls/openbao.crt"
  tls_key_file    = "/openbao/tls/openbao.key"
}

storage "raft" {
  path                      = "/openbao/data"
  node_id                   = "platform-openbao"
  performance_multiplier    = 5
  snapshot_threshold        = 8192
  snapshot_interval         = "120s"
}

seal "azurekeyvault" {
  tenant_id  = "__AZURE_TENANT_ID__"
  vault_name = "__PLATFORM_KEY_VAULT_NAME__"
  key_name   = "openbao-unseal"
}
