## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_artifact_registry_repository.artifact_registry](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository_iam_member.permissions](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_policy.policy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_policy) | resource |
| [google_project_service.artifact_registry_api](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_iam_policy.admin](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/iam_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_authoritative_permissions"></a> [authoritative\_permissions](#input\_authoritative\_permissions) | Set authoritative\_permissions | `bool` | `true` | no |
| <a name="input_base_name"></a> [base\_name](#input\_base\_name) | Name for the resource | `string` | n/a | yes |
| <a name="input_cleanup_policies"></a> [cleanup\_policies](#input\_cleanup\_policies) | Set a list of cleanup\_policies | <pre>map(object({<br>    action = optional(string)<br>    condition = optional(object({<br>      tag_state             = optional(string, null)<br>      tag_prefixes          = optional(list(string))<br>      version_name_prefixes = optional(list(string))<br>      package_name_prefixes = optional(list(string))<br>      older_than            = optional(string)<br>      newer_than            = optional(string)<br>    }), null)<br>    most_recent_versions = optional(object({<br>      package_name_prefixes = optional(list(string))<br>      keep_count            = optional(number)<br>    }), null)<br>  }))</pre> | `{}` | no |
| <a name="input_cleanup_policy_dry_run"></a> [cleanup\_policy\_dry\_run](#input\_cleanup\_policy\_dry\_run) | Set cleanup\_policy\_dry\_run | `bool` | `true` | no |
| <a name="input_format"></a> [format](#input\_format) | Format Artifact Registry Repo | `string` | `"DOCKER"` | no |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project source | `string` | n/a | yes |
| <a name="input_immutable_tags"></a> [immutable\_tags](#input\_immutable\_tags) | Set immutable\_tags flag | `bool` | `false` | no |
| <a name="input_permissions"></a> [permissions](#input\_permissions) | Permissions Artifact Registry | <pre>map(object({<br>    members = list(string)<br>    roles   = list(string)<br>  }))</pre> | `{}` | no |
| <a name="input_region_name"></a> [region\_name](#input\_region\_name) | Region name | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_artifact_repo_id"></a> [artifact\_repo\_id](#output\_artifact\_repo\_id) | The ID of the Artifact Registry repository |
| <a name="output_artifact_repo_name"></a> [artifact\_repo\_name](#output\_artifact\_repo\_name) | The name of the Artifact Registry repository |
| <a name="output_artifact_repo_url"></a> [artifact\_repo\_url](#output\_artifact\_repo\_url) | Url of the artifact registry |
