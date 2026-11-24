#------------------------------------------------------------------------------
# App registration + service principal (enterprise application)
#
# AVM covers ARM resources only; Entra ID objects use the azuread provider.
#------------------------------------------------------------------------------

resource "azuread_application" "this" {
  display_name     = var.app_registration_name
  description      = var.description
  sign_in_audience = var.sign_in_audience

  owners                  = var.owners
  group_membership_claims = var.group_membership_claims
  identifier_uris         = length(var.identifier_uris) > 0 ? var.identifier_uris : null

  dynamic "api" {
    for_each = length(var.expose_api_scopes) > 0 ? [1] : []

    content {
      dynamic "oauth2_permission_scope" {
        for_each = var.expose_api_scopes
        content {
          id                         = oauth2_permission_scope.value.id
          value                      = oauth2_permission_scope.value.value
          type                       = oauth2_permission_scope.value.type
          enabled                    = oauth2_permission_scope.value.enabled
          admin_consent_display_name = oauth2_permission_scope.value.admin_consent_display_name
          admin_consent_description  = oauth2_permission_scope.value.admin_consent_description
          user_consent_display_name  = oauth2_permission_scope.value.user_consent_display_name
          user_consent_description   = oauth2_permission_scope.value.user_consent_description
        }
      }
    }
  }

  dynamic "web" {
    for_each = var.single_sign_on == null ? [] : [1]

    content {
      redirect_uris = var.single_sign_on.redirect_uris
      homepage_url  = var.single_sign_on.homepage_url
      logout_url    = var.single_sign_on.logout_url

      implicit_grant {
        access_token_issuance_enabled = var.single_sign_on.access_token_issuance_enabled
        id_token_issuance_enabled     = var.single_sign_on.id_token_issuance_enabled
      }
    }
  }

  dynamic "public_client" {
    for_each = var.single_sign_on == null || length(var.single_sign_on.public_client_redirect_uris) == 0 ? [] : [1]

    content {
      redirect_uris = var.single_sign_on.public_client_redirect_uris
    }
  }

  dynamic "optional_claims" {
    for_each = var.single_sign_on == null ? [] : [1]

    content {
      dynamic "access_token" {
        for_each = toset(var.single_sign_on.access_token_optional_claims)
        content {
          name      = access_token.value
          essential = false
        }
      }

      dynamic "id_token" {
        for_each = toset(var.single_sign_on.id_token_optional_claims)
        content {
          name      = id_token.value
          essential = false
        }
      }

      dynamic "saml2_token" {
        for_each = toset(var.single_sign_on.saml2_token_optional_claims)
        content {
          name      = saml2_token.value
          essential = false
        }
      }
    }
  }

  dynamic "required_resource_access" {
    for_each = var.api_permissions

    content {
      resource_app_id = required_resource_access.key

      dynamic "resource_access" {
        for_each = required_resource_access.value.application_roles
        content {
          id   = local.resource_apis[required_resource_access.key].app_role_ids[resource_access.value]
          type = "Role"
        }
      }

      dynamic "resource_access" {
        for_each = required_resource_access.value.delegated_scopes
        content {
          id   = local.resource_apis[required_resource_access.key].oauth2_permission_scope_ids[resource_access.value]
          type = "Scope"
        }
      }
    }
  }
}

# Create a service principal (enterprise application) for the app registration
# to enable role assignments and authentication.
resource "azuread_service_principal" "this" {
  client_id                    = azuread_application.this.client_id
  owners                       = var.owners
  app_role_assignment_required = var.app_role_assignment_required
}

#------------------------------------------------------------------------------
# Admin consent (opt-in)
#------------------------------------------------------------------------------

# Optional: grant admin consent for the application permissions requested above.
resource "azuread_app_role_assignment" "consent" {
  for_each = var.grant_admin_consent ? merge([
    for api_key, perms in var.api_permissions : {
      for role in perms.application_roles :
      "${api_key}/${role}" => {
        api_key = api_key
        role    = role
      }
    }
  ]...) : {}

  principal_object_id = azuread_service_principal.this.object_id
  resource_object_id  = local.resource_apis[each.value.api_key].object_id
  app_role_id         = local.resource_apis[each.value.api_key].app_role_ids[each.value.role]
}

# Tenant-wide admin consent for the delegated permissions above. Required for
# headless integrations with no interactive user to consent.
resource "azuread_service_principal_delegated_permission_grant" "consent" {
  for_each = var.grant_delegated_admin_consent ? {
    for api_key, perms in var.api_permissions : api_key => perms
    if length(perms.delegated_scopes) > 0
  } : {}

  service_principal_object_id          = azuread_service_principal.this.object_id
  resource_service_principal_object_id = local.resource_apis[each.key].object_id
  claim_values                         = each.value.delegated_scopes
}

#------------------------------------------------------------------------------
# Exposed API pre-authorization (self-grant of own scopes)
#------------------------------------------------------------------------------

resource "azuread_application_pre_authorized" "own_scopes" {
  count = var.pre_authorize_own_scopes && length(var.expose_api_scopes) > 0 ? 1 : 0

  application_id       = azuread_application.this.id
  authorized_client_id = azuread_application.this.client_id

  permission_ids = [for scope in var.expose_api_scopes : scope.id]
}

#------------------------------------------------------------------------------
# Optional: client secret. Lands in Terraform state - see variable description.
#------------------------------------------------------------------------------

# Creation-time anchor for the client secret expiry (stable across plans).
resource "time_static" "client_secret" {
  count = var.create_client_secret ? 1 : 0
}

resource "azuread_application_password" "this" {
  count = var.create_client_secret ? 1 : 0

  application_id = azuread_application.this.id
  display_name   = coalesce(var.client_secret_display_name, var.app_registration_name)

  # Secret expiry = creation time + client_secret_end_date_relative.
  end_date = timeadd(time_static.client_secret[0].rfc3339, var.client_secret_end_date_relative)
}
