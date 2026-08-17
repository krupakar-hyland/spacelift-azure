location                          = "eastus"
resource_group_name               = "rg-spacelift-demo-prod"
storage_account_name              = "stspldemoprod001"
storage_account_tier              = "Standard"
storage_account_replication_type  = "GRS"
storage_container_name            = "data"

common_tags = {
  Environment = "production"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo"
}
