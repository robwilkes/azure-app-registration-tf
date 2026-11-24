#------------------------------------------------------------------------------
# Optional Azure RBAC role assignments for the service principal.
#
# Role definitions are resolved at plan time with data.azurerm_role_definition
# (a missing or misspelled role fails the plan), then created through the basic
# interface of the AVM module Azure/avm-res-authorization-roleassignment.
# Instantiated only when role_assignments is non-empty.
#------------------------------------------------------------------------------

locals {
  role_definitions_by_name = {
    for key, assignment in var.role_assignments : key => assignment
    if try(assignment.role_definition_name, null) != null
  }

  role_definitions_by_id = {
    for key, assignment in var.role_assignments : key => assignment
    if try(assignment.role_definition_name, null) == null
  }

  # Where the role definition lookup searches: the definition's own scope when
  # given (custom roles), otherwise the assignment scope (built-ins).
  role_definition_lookup_scopes = {
    for key, assignment in var.role_assignments : key =>
    coalesce(try(assignment.role_definition_scope, null), assignment.scope)
  }

  resolved_role_definition_ids = merge(
    { for key, rd in data.azurerm_role_definition.by_name : key => rd.id },
    { for key, rd in data.azurerm_role_definition.by_id : key => rd.id },
  )
}

data "azurerm_role_definition" "by_name" {
  for_each = local.role_definitions_by_name

  name  = each.value.role_definition_name
  scope = local.role_definition_lookup_scopes[each.key]
}

data "azurerm_role_definition" "by_id" {
  for_each = local.role_definitions_by_id

  role_definition_id = each.value.role_definition_id
  scope              = local.role_definition_lookup_scopes[each.key]
}

module "role_assignments" {
  count = length(var.role_assignments) > 0 ? 1 : 0

  source  = "Azure/avm-res-authorization-roleassignment/azurerm"
  version = "0.3.1"

  role_assignments_azure_resource_manager = {
    for key, assignment in var.role_assignments : key => {
      principal_id                     = azuread_service_principal.this.object_id
      principal_type                   = "ServicePrincipal"
      role_definition_id               = local.resolved_role_definition_ids[key]
      scope                            = assignment.scope
      skip_service_principal_aad_check = var.skip_service_principal_aad_check
    }
  }

  enable_telemetry = var.enable_telemetry
}
