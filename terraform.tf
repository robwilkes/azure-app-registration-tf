terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    # azurerm is only used by the optional role_assignments feature, which is
    # delegated to the AVM role assignment module (requires azurerm >= 3.7).
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.7, < 5.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0, < 4.0"
    }
    # time_static anchors the client secret expiry (see main.tf).
    time = {
      source  = "hashicorp/time"
      version = ">= 0.12, < 1.0"
    }
  }
}
