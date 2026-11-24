# azure-app-registration-tf

Reusable Terraform module for creating **Microsoft Entra ID app registrations** with the
resource-API permissions, admin consent, client secret, exposed API and (optional) Azure RBAC
setup that an integration needs.

The module is **integration-agnostic**: it creates the Entra ID side of any app registration -
it makes no assumptions about which application consumes it.

There is no Azure Verified Module for Entra ID app registrations (AVM covers ARM resources
only), so the module uses the `azuread` provider directly; Azure RBAC role assignments are
delegated to the AVM module
[`Azure/avm-res-authorization-roleassignment`](https://registry.terraform.io/modules/Azure/avm-res-authorization-roleassignment/azurerm).

## What it creates

- An `azuread_application` (app registration) with the requested **API permissions** and
  optionally: exposed API scopes, identifier URIs, interactive SSO (redirect URIs, implicit
  grant flags, optional claims), sign-in audience.
- An `azuread_service_principal` (enterprise application).
- Optional tenant-wide **admin consent**: application permissions
  (`grant_admin_consent`) and delegated permissions (`grant_delegated_admin_consent`).
- Optional `azuread_application_pre_authorized` for an app that consumes its own exposed scopes.
- Optional client secret (`create_client_secret`), returned as a sensitive output.
- Optional **Azure RBAC role assignments** for the service principal at any ARM scope
  (built-in roles by name, custom roles by GUID).

## Usage

```hcl
module "example" {
  source = "./modules/azure-app-registration"   # or git::https://github.com/<org>/azure-app-registration-tf.git?ref=v0.1.0

  app_registration_name = "Example Integration App"

  api_permissions = {
    # Microsoft Graph (well-known client ID)
    "00000003-0000-0000-c000-000000000000" = {
      delegated_scopes = ["User.Read"]
    }
    # Resource APIs whose client ID is not documented are keyed by display name
    "Log Analytics API" = {
      delegated_scopes             = ["Data.Read"]
      resource_api_identifier_type = "display_name"
    }
  }

  # Headless integrations cannot consent interactively - grant consent as admin.
  # Security-relevant inputs have no defaults: every grant/decision is written out.
  grant_delegated_admin_consent = true
  grant_admin_consent           = false
  pre_authorize_own_scopes      = false

  create_client_secret            = true
  client_secret_end_date_relative = "8760h"

  role_assignments = {
    reader = {
      role_definition_name = "Reader"
      scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
    }
  }
}

output "example_client_id" {
  value = module.example.client_id
}
```

A runnable example is in [`basic`](basic/main.tf).

## Key inputs

Inputs that can grant or widen access have **no defaults** by design: callers must state them
explicitly, so a reviewer/auditor sees every permission, secret, expiry and RBAC scope in the
calling configuration, and a future module release can never silently change what is granted.
Write `grant_admin_consent = false` or `role_assignments = {}` to record a deliberate "no".

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `app_registration_name` | Display name of the app registration | `string` | n/a (required) |
| `sign_in_audience` | Entra audience; `AzureADMyOrg` (single tenant) or `AzureADandMultipleOrganizations` (multi-tenant) | `string` | `"AzureADMyOrg"` |
| `api_permissions` | API permissions keyed by resource-API client ID or display name; `application_roles` (app-only) and/or `delegated_scopes` (delegated) by **name** | `map(object)` | `{}` |
| `grant_admin_consent` | Tenant-wide admin consent for application permissions | `bool` | n/a (required) |
| `grant_delegated_admin_consent` | Tenant-wide admin consent for delegated permissions | `bool` | n/a (required) |
| `create_client_secret` | Create a client secret (lands in Terraform state) | `bool` | n/a (required) |
| `client_secret_end_date_relative` | Secret lifetime, e.g. `"8760h"`; required whenever `create_client_secret = true` | `string` | n/a (required with a secret) |
| `identifier_uris` | Static `spn://` / `api://` identifier URIs | `list(string)` | `[]` |
| `expose_api_scopes` | OAuth2 scopes the app exposes as its own API | `list(object)` | `[]` |
| `pre_authorize_own_scopes` | Let the app request its own exposed scopes | `bool` | n/a (required) |
| `single_sign_on` | Interactive SSO config: web/public-client redirect URIs, implicit-grant flags, optional claims | `object` | `null` |
| `app_role_assignment_required` | Require user assignment before token requests | `bool` | `null` |
| `role_assignments` | Azure RBAC grants to the service principal (`role_definition_name` **or** `role_definition_id` + optional `role_definition_scope`, plus assignment `scope`); pass `{}` for an explicit "no RBAC" | `map(object)` | n/a (required) |
| `skip_service_principal_aad_check` | Skip azurerm's SP existence check for role assignments (only for first-apply replication races) | `bool` | `false` |
| `owners` | Object IDs owning the app/SP | `list(string)` | `null` |
| `enable_telemetry` | AVM telemetry in the role-assignment child module | `bool` | `true` |

## Outputs

| Name | Description |
|------|-------------|
| `application_object_id` | Object ID of the app registration |
| `client_id` | Application (client) ID - give to the integration |
| `directory_tenant_id` | Directory (tenant) ID |
| `service_principal_object_id` | Object ID of the enterprise application |
| `client_secret` | Secret value (`sensitive`, `null` unless created) |
| `role_assignments` | Created role assignments as reported by the AVM child module |

## Deployment permissions

- Creating the app registration and service principal requires an Entra role such as
  **Application Administrator** or **Cloud Application Administrator**.
- `grant_admin_consent` / `grant_delegated_admin_consent` additionally require
  **Global Administrator** or **Privileged Role Administrator** - plan/deploy with an elevated
  identity when enabling these, then rotate to a least-privilege identity for day-2 runs.
- `role_assignments` requires **Owner** or **Role Based Access Control Administrator** at the
  assignment scope (and, for custom roles, that the referenced definition already exists).

## Post-deployment checklist

1. Hand the integration its `client_id`, `directory_tenant_id` and (if created)
   `terraform output -raw <module>.client_secret`.
2. Configure the integrating application's side (e.g. its OAuth/OIDC connection settings) using those values.
3. If `create_client_secret = true`, record the expiry (`client_secret_end_date_relative`) and
   rotate before it lapses: changing any of the secret's arguments in the config forces a new
   secret; re-apply and update the integrating application with `terraform output -raw ...`.

## Security considerations

- **Client secrets land in Terraform state.** Only enable `create_client_secret` when the state
  backend is access-controlled; otherwise create the secret in the portal or via a secret
  manager and inject it. Entra tenant policies may cap secret lifetime below
  `client_secret_end_date_relative`.
- **Admin consent is tenant-wide.** Keep permission lists minimal; prefer application
  permissions scoped to the smallest resource set (e.g. resource group- or resource-level
  roles rather than subscription-wide where the integration supports it).
- Role assignments to the service principal are **at the ARM scope you pass**; the module never
  assigns roles to the deploying user.
- Set `app_role_assignment_required = true` for user-facing apps with assignment required.

## Implementation notes

- **Permissions are resolved by name at plan time.** The module reads
  `data "azuread_service_principal"` for each resource API and maps your permission names
  through its `app_role_ids` / `oauth2_permission_scope_ids` maps. A typo (or a resource API
  that has never been registered in the tenant) fails the plan rather than deploying a wrong
  GUID. Microsoft Graph's client ID (`00000003-0000-0000-c000-000000000000`) is safe to hardcode;
  for other APIs prefer the documented client ID; only fall back to
  `resource_api_identifier_type = "display_name"` when no client ID is published (e.g.
  "Log Analytics API") - display names are localized in some tenants.
- **Delegated admin consent** uses
  `azuread_service_principal_delegated_permission_grant`; this is how headless integrations
  documented as needing delegated scopes get consent without an interactive sign-in.
- **Role assignments**: the module resolves each role definition at plan time via
  `data "azurerm_role_definition"` (built-ins by name at the assignment scope; custom definitions by
  name/GUID at `role_definition_scope`) and hands the resolved full role definition IDs to the AVM
  module [`Azure/avm-res-authorization-roleassignment`](https://registry.terraform.io/modules/Azure/avm-res-authorization-roleassignment/azurerm)
  basic interface (`role_assignments_azure_resource_manager`), which creates the
  `azurerm_role_assignment` resources (pinned, see [role_assignments.tf](role_assignments.tf)).
  The `azurerm` provider is only required when `role_assignments` is non-empty.
- **Client secret expiry** is implemented as an absolute `end_date` computed with
  `timeadd()` from a `time_static` resource that captures the creation timestamp once.
  azuread's `end_date_relative` gained a deprecation warning in 3.10.0 (it will be removed in a
  future major version); anchoring on `timestamp()` instead would force secret recreation on
  every plan. Changing `client_secret_end_date_relative` still rotates the secret, as before.
- `api://<client-id>` identifier URIs for an app's own API cannot be set inline (circular
  dependency); create `azuread_application_identifier_uri` in the caller keyed on the module's
  `client_id` output.
