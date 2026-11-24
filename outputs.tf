#------------------------------------------------------------------------------
# Identifiers typically handed to the integrating application
#------------------------------------------------------------------------------

output "application_object_id" {
  value       = azuread_application.this.object_id
  description = "Object ID of the application registration."
}

output "client_id" {
  value       = azuread_application.this.client_id
  description = "Application (client) ID of the app registration."
}

output "directory_tenant_id" {
  value       = azuread_service_principal.this.application_tenant_id
  description = "Directory (tenant) ID."
}

output "service_principal_object_id" {
  value       = azuread_service_principal.this.object_id
  description = "Object ID of the enterprise application (service principal)."
}

output "client_secret" {
  value       = var.create_client_secret ? azuread_application_password.this[0].value : null
  sensitive   = true
  description = "Client secret for the app registration (null unless create_client_secret = true). Retrieve with 'terraform output -raw <module>.client_secret' at the root module."
}

#------------------------------------------------------------------------------
# Optional role assignments
#------------------------------------------------------------------------------

output "role_assignments" {
  value       = length(var.role_assignments) > 0 ? module.role_assignments[0].role_assignments : {}
  description = "Created Azure RBAC role assignments keyed by the keys of var.role_assignments; each value holds role_definition_id, principal_id and scope (as reported by the AVM role assignment module)."
}
