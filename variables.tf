variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-spacelift-demo"
}

variable "storage_account_name" {
  description = "Name of the storage account (must be globally unique, lowercase alphanumeric)"
  type        = string
  default     = "stsplfdemo123"

  validation {
    condition     = length(var.storage_account_name) >= 3 && length(var.storage_account_name) <= 24
    error_message = "Storage account name must be between 3 and 24 characters."
  }
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "GRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Valid replication types are: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "storage_container_name" {
  description = "Name of the storage container"
  type        = string
  default     = "data"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "Spacelift"
  }
}
