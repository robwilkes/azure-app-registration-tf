terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.7, < 5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0, < 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

# Replace the placeholder subscription ID with the target subscription before planning.
module "example_app_registration" {
  # In your own configuration, consume the published module, e.g.:
  # source = "git::https://github.com/<org>/azure-app-registration-tf.git?ref=v0.1.0"
  source = "../"

  app_registration_name = "Example-Integration-ExampleOrg"
  description           = "Example integration app registration created by the azure-app-registration module."

  api_permissions = {
    # Microsoft Graph, keyed by its well-known client ID.
    "00000003-0000-0000-c000-000000000000" = {
      application_roles = ["User.Read.All"]
      delegated_scopes  = ["User.Read"]
    }
  }

  grant_admin_consent             = true
  grant_delegated_admin_consent   = true
  pre_authorize_own_scopes        = false
  create_client_secret            = true
  client_secret_end_date_relative = "730h"

  role_assignments = {
    subscription_reader = {
      role_definition_name = "Reader"
      scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

output "client_id" {
  value       = module.example_app_registration.client_id
  description = "Application (client) ID to give to the integration."
}

output "directory_tenant_id" {
  value       = module.example_app_registration.directory_tenant_id
  description = "Directory (tenant) ID to give to the integration."
}

output "client_secret" {
  value       = module.example_app_registration.client_secret
  sensitive   = true
  description = "Client secret to give to the integration. Prefer 'terraform output -raw client_secret'."
}
