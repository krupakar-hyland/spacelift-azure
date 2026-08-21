location                          = "eastus"
resource_group_name               = "rg-spacelift-demo-staging"
storage_account_name              = "stspldemostg001"
storage_account_tier              = "Standard"
storage_account_replication_type  = "RAGRS"
storage_container_name            = "data"

common_tags = {
  Environment = "staging"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo"
}
