data "google_iam_policy" "admin" {
  count = var.authoritative_permissions == true ? 1 : 0
  dynamic "binding" {
    for_each = local.iam_flatten
    content {
      role    = binding.value.role
      members = [binding.value.member]
    }
  }
}

resource "google_artifact_registry_repository_iam_policy" "policy" {
  count       = var.authoritative_permissions == true ? 1 : 0
  project     = var.gcp_project_id
  location    = var.region_name
  repository  = google_artifact_registry_repository.artifact_registry.name
  policy_data = data.google_iam_policy.admin[0].policy_data
}


locals {
  iam_flatten = { for a in chunklist(flatten([for i, k in var.permissions : setproduct([i], k.members, k.roles)]), 3) : "${a[0]}_${a[1]}_${a[2]}" => { role = a[2], member = a[1] } }
}


resource "google_artifact_registry_repository_iam_member" "permissions" {
  for_each   = var.authoritative_permissions == false ? local.iam_flatten : {}
  project    = var.gcp_project_id
  location   = var.region_name
  repository = google_artifact_registry_repository.artifact_registry.name
  role       = each.value.role
  member     = each.value.member
}

