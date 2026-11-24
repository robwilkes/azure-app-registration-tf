#------------------------------------------------------------------------------
# Resource API lookups
#
# Resolve the service principals of the resource APIs (Microsoft Graph,
# Log Analytics API, ...) so permission *names* can be translated to IDs at
# plan time - avoids hardcoding permission GUIDs.
#------------------------------------------------------------------------------

data "azuread_service_principal" "resource_apis_by_client_id" {
  for_each = {
    for key, perms in var.api_permissions :
    key => perms
    if try(perms.resource_api_identifier_type, "client_id") == "client_id"
  }

  client_id = each.key
}

data "azuread_service_principal" "resource_apis_by_display_name" {
  for_each = {
    for key, perms in var.api_permissions :
    key => perms
    if try(perms.resource_api_identifier_type, "client_id") == "display_name"
  }

  display_name = each.key
}

locals {
  # Maps each api_permissions key to the resolved resource API service principal.
  # Each key is looked up by exactly one identifier type (validated in variables.tf).
  resource_apis = {
    for key, perms in var.api_permissions :
    key => coalesce(
      try(data.azuread_service_principal.resource_apis_by_client_id[key], null),
      try(data.azuread_service_principal.resource_apis_by_display_name[key], null),
    )
  }
}
