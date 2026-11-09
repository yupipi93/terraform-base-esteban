README.md updated successfully
s.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_managed_ssl_certificate.base](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_managed_ssl_certificate) | resource |
| [random_id.base](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_base_name"></a> [base\_name](#input\_base\_name) | Name for the resource | `string` | n/a | yes |
| <a name="input_domain"></a> [domain](#input\_domain) | List of domains to add | `list(string)` | `[]` | no |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project source | `string` | n/a | yes |
| <a name="input_module_name"></a> [module\_name](#input\_module\_name) | Constant for module | `string` | `"cert"` | no |
| <a name="input_region_name"></a> [region\_name](#input\_region\_name) | Region name | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_certificate_id"></a> [certificate\_id](#output\_certificate\_id) | The unique identifier for the resource. |
| <a name="output_id"></a> [id](#output\_id) | An identifier for the resource with format projects/{{project}}/global/sslCertificates/{{name}} |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The URI of the created resource. |
| <a name="output_subject_alternative_names"></a> [subject\_alternative\_names](#output\_subject\_alternative\_names) | Domains associated with the certificate via Subject Alternative Name. |