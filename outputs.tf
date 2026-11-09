# Root outputs: what a deploy, a DNS change or a CI job needs after an apply,
# read with `terraform output` instead of from state. Every output is an empty
# map or null when its feature is absent from the workspace. None of them
# carries a secret: passwords stay in Secret Manager.

output "load_balancer_ip" {
  description = "Global address of the HTTPS load balancer (and its HTTP redirect). Null without an lb section."
  value       = one(google_compute_global_address.lb_static_ip[*].address)
}

output "load_balancer_domains" {
  description = "Domains on the load balancer certificate (lb.domain). Point their A records at load_balancer_ip."
  value       = local.lb_enabled ? flatten([try(local.settings.lb.domain, [])]) : []
}

output "cloud_run_service_urls" {
  description = "run.app URL of each Cloud Run service, keyed by its app.service key."
  value       = { for key, service in module.cloud_run_services : key => service.cloudrun_service_url }
}

output "cloud_sql_connection_names" {
  description = "Connection name (project:region:instance) of each Cloud SQL instance, keyed by its database key."
  value       = { for key, instance in module.cloud_sql : key => instance.connection_name }
}

output "artifact_registry_service_urls" {
  description = "Docker registry path of each per-service repository, keyed by its app.service key."
  value       = { for key, repo in module.artifact_registry : key => repo.artifact_repo_url }
}

output "artifact_registry_standalone_urls" {
  description = "Registry path of each repository under artifact_repos, keyed by its key."
  value       = { for key, repo in google_artifact_registry_repository.standalone : key => repo.registry_uri }
}

output "wif_providers" {
  description = "Full resource name of each Workload Identity Federation provider, keyed pool/provider. The CI auth step takes it as workload_identity_provider."
  value       = { for key, provider in google_iam_workload_identity_pool_provider.wif : key => provider.name }
}

output "wif_service_accounts" {
  description = "Email of the service account each wif binding impersonates, keyed by the binding's service_account."
  value       = local.wif_sa_email
}

output "audit_archive_bucket" {
  description = "Log bucket that archives Cloud Audit Logs (logging.audit_archive). Null when it is not set."
  value       = one(google_logging_project_bucket_config.audit_archive[*].id)
}
