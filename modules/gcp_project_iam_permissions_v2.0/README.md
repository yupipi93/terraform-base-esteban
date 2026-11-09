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
| [google_project_iam_member.permissions](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_permissions"></a> [permissions](#input\_permissions) | List the members and list of roles to assign | <pre>list(object({<br>    members = list(string)<br>    roles   = list(string)<br>  }))</pre> | `{}` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP Project source id | `string` | n/a | yes |

## Outputs

No outputs.
