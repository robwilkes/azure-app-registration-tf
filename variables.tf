#------------------------------------------------------------------------------
# General
#------------------------------------------------------------------------------

variable "app_registration_name" {
  type        = string
  description = "Display name of the Entra ID application registration."
}

variable "description" {
  type        = string
  default     = null
  description = "Optional description shown on the application registration."
}

variable "sign_in_audience" {
  type        = string
  default     = "AzureADMyOrg"
  description = "Microsoft Entra audience for the application. Typical values: 'AzureADMyOrg' (single tenant, the default) or 'AzureADandMultipleOrganizations' (multi-tenant)."

  validation {
    condition = contains([
      "AzureADMyOrg",
      "AzureADandMultipleOrganizations",
      "AzureADMySite",
      "PersonalMicrosoftAccount",
    ], var.sign_in_audience)
    error_message = "sign_in_audience must be one of: AzureADMyOrg, AzureADandMultipleOrganizations, AzureADMySite, PersonalMicrosoftAccount."
  }
}

variable "owners" {
  type        = list(string)
  default     = null
  description = "Object IDs of users/groups that own the application and service principal. Defaults to the deploying principal when null."
}

variable "group_membership_claims" {
  type        = list(string)
  default     = null
  description = "Which group memberships are emitted in tokens: 'SecurityGroup', 'DirectoryRole', 'ApplicationGroup'. Keep the list short - overage claims apply above 200 groups."

  validation {
    condition     = var.group_membership_claims == null ? true : alltrue([for g in var.group_membership_claims : contains(["SecurityGroup", "DirectoryRole", "ApplicationGroup"], g)])
    error_message = "group_membership_claims entries must be one of: SecurityGroup, DirectoryRole, ApplicationGroup."
  }
}

variable "identifier_uris" {
  type        = list(string)
  default     = []
  description = "Identifier URIs (spn:// or api://) for the application. Note: a value of 'api://<client-id>' cannot reference the client ID Terraform is creating in the same module (dependency cycle); callers that need that pattern create a separate azuread_application_identifier_uri resource keyed off the module's client_id output instead."
}

#------------------------------------------------------------------------------
# API permissions
#
# Permissions are referenced by *name* and resolved against the resource API's
# service principal at plan time, so typos fail the plan instead of deploying
# the wrong permission GUID.
#------------------------------------------------------------------------------

variable "api_permissions" {
  type = map(object({
    application_roles            = optional(list(string), [])
    delegated_scopes             = optional(list(string), [])
    resource_api_identifier_type = optional(string, "client_id")
  }))
  default     = {}
  description = <<-EOT
    API permissions requested by the application, keyed by an identifier of the resource API:
      - `resource_api_identifier_type = "client_id"` (default): the key is the resource API's well-known client ID,
        e.g. "00000003-0000-0000-c000-000000000000" for Microsoft Graph.
      - `resource_api_identifier_type = "display_name"`: the key is the resource API's display name as it appears
        under 'APIs my organization uses', e.g. "Log Analytics API". Use this when the well-known client ID is not
        documented; if the service principal has never been registered in the tenant the plan fails with a clear
        error and you must fall back to the client ID.
    `application_roles` are application permissions (app-only, e.g. "User.Read.All"); `delegated_scopes` are
    delegated permissions (e.g. "User.Read").
  EOT

  validation {
    condition     = alltrue([for k, v in var.api_permissions : contains(["client_id", "display_name"], try(v.resource_api_identifier_type, "client_id"))])
    error_message = "api_permissions.resource_api_identifier_type must be either 'client_id' or 'display_name'."
  }
}

variable "grant_admin_consent" {
  type        = bool
  description = "Grants tenant-wide admin consent for the *application* permissions (application_roles) requested above. Requires a privileged Entra role such as Global Administrator or Privileged Role Administrator. No default: must be set explicitly (false = no consent granted)."
}

variable "grant_delegated_admin_consent" {
  type        = bool
  description = <<-EOT
    Grants tenant-wide admin consent for the *delegated* permissions (delegated_scopes) requested above via the
    Graph service principal. Requires a privileged Entra role. Headless integrations (client credentials flows
    documented as needing delegated scopes) cannot consent
    interactively, so this is how they get consent. No default: must be set explicitly (false = no consent granted).
  EOT
}

#------------------------------------------------------------------------------
# Client secret
#------------------------------------------------------------------------------

variable "create_client_secret" {
  type        = bool
  description = "Creates a client secret for the application. WARNING: the secret value lands in Terraform state; it is exposed as the sensitive output `client_secret` and retrieved with 'terraform output -raw'. If your state backend is not tightly controlled, create the secret manually instead. No default: must be set explicitly."
}

variable "client_secret_display_name" {
  type        = string
  default     = null
  description = "Display name for the client secret. Defaults to the application name when null."
}

variable "client_secret_end_date_relative" {
  type        = string
  default     = null
  description = <<-EOT
    Lifetime of the client secret, e.g. "730h" (30 days) or "8760h" (1 year). Entra tenants may enforce
    a shorter maximum lifetime. Changing this value rotates the secret. Required when
    create_client_secret = true, so every secret has a reviewer-visible expiry.
  EOT

  validation {
    condition     = var.create_client_secret ? var.client_secret_end_date_relative != null : true
    error_message = "client_secret_end_date_relative must be set explicitly when create_client_secret = true, e.g. \"8760h\" (1 year)."
  }
}

#------------------------------------------------------------------------------
# Exposed API (apps that expose their own OAuth2 scopes)
#------------------------------------------------------------------------------

variable "expose_api_scopes" {
  type = list(object({
    id                         = string
    value                      = string
    admin_consent_display_name = string
    admin_consent_description  = string
    type                       = optional(string, "User")
    enabled                    = optional(bool, true)
    user_consent_display_name  = optional(string)
    user_consent_description   = optional(string)
  }))
  default     = []
  description = "OAuth2 permission scopes exposed by this application's own API. `id` must be a stable GUID chosen by you (it is the scope's permission ID). Combine with identifier_uris (typically 'api://<client-id>' added via a separate azuread_application_identifier_uri resource, because it references the client ID Terraform only knows after apply)."

  validation {
    condition     = alltrue([for s in var.expose_api_scopes : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", s.id))])
    error_message = "expose_api_scopes[].id must be a valid GUID."
  }

  validation {
    condition     = alltrue([for s in var.expose_api_scopes : contains(["User", "Admin"], try(s.type, "User"))])
    error_message = "expose_api_scopes[].type must be 'User' or 'Admin'."
  }
}

variable "pre_authorize_own_scopes" {
  type        = bool
  description = "Pre-authorizes the application to request its own exposed scopes (the 'pre-authorized applications' entry the portal creates for itself). Requires expose_api_scopes to be non-empty. No default: must be set explicitly (false = no pre-authorization)."
}

#------------------------------------------------------------------------------
# Interactive single sign-on (public/client apps, e.g. OIDC or SAML web sign-in)
#------------------------------------------------------------------------------

variable "single_sign_on" {
  type = object({
    redirect_uris                 = optional(list(string), [])
    homepage_url                  = optional(string)
    logout_url                    = optional(string)
    access_token_issuance_enabled = optional(bool, false)
    id_token_issuance_enabled     = optional(bool, false)
    public_client_redirect_uris   = optional(list(string), [])
    access_token_optional_claims  = optional(list(string), [])
    id_token_optional_claims      = optional(list(string), [])
    saml2_token_optional_claims   = optional(list(string), [])
  })
  default     = null
  description = "Optional interactive SSO configuration: web redirect URIs, (implicit) token issuance flags, mobile/desktop public client redirect URIs, and optional claims (e.g. 'groups', 'email') emitted into access/id/SAML tokens. Leave null for headless integrations."
}

#------------------------------------------------------------------------------
# Service principal / enterprise application
#------------------------------------------------------------------------------

variable "app_role_assignment_required" {
  type        = bool
  default     = null
  description = "When true, assignment of the enterprise application is required before users or other service principals can request tokens (user assignment enforced in the portal)."
}

#------------------------------------------------------------------------------
# Azure RBAC role assignments for the service principal (optional)
#------------------------------------------------------------------------------

variable "role_assignments" {
  type = map(object({
    role_definition_name  = optional(string)
    role_definition_id    = optional(string)
    role_definition_scope = optional(string)
    scope                 = string
  }))
  description = <<-EOT
    Azure RBAC role assignments granted to the service principal. No default: must be set explicitly;
    use `role_assignments = {}` to state "no Azure RBAC" so reviewers see the decision.
    Each entry references a role definition
    either by name (built-in roles, e.g. "Reader", "Log Analytics Contributor", or a custom role definition
    name) or by GUID (`role_definition_id`); pass `role_definition_scope` when the definition lives at a
    different scope than the assignment (e.g. custom role definitions). The lookup happens at plan time via
    `data.azurerm_role_definition`, so a missing role definition fails the plan. `scope` is where the
    assignment applies, e.g. "/subscriptions/<id>". Assignments are created through the AVM module
    Azure/avm-res-authorization-roleassignment.
  EOT

  validation {
    condition     = alltrue([for k, r in var.role_assignments : try(r.role_definition_name, null) != null || try(r.role_definition_id, null) != null])
    error_message = "Each role_assignments entry must set either role_definition_name or role_definition_id."
  }

  validation {
    condition     = alltrue([for k, r in var.role_assignments : can(regex("^/", r.scope))])
    error_message = "role_assignments[].scope must be a fully-qualified Azure resource ID (starting with '/'), e.g. '/subscriptions/<uuid>'."
  }
}

variable "skip_service_principal_aad_check" {
  type        = bool
  default     = false
  description = "Skips the Entra ID existence check azurerm performs for service principal role assignments. Only needed if a role assignment races with replication of the freshly-created service principal ('Service Principal with app ID ... does not exist' style errors on first apply)."
}

#------------------------------------------------------------------------------
# Telemetry
#------------------------------------------------------------------------------

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Enables Microsoft's AVM telemetry inside the child AVM modules (used by role_assignments). See https://aka.ms/avm/telemetryinfo."
}
