locals {
  iam_flatten = { for a in chunklist(flatten([for i, k in var.permissions : setproduct([i], [k.account], k.permissions)]), 3) : "${a[0]}_${a[2]}" => {
    account = a[1],
    role    = a[2]
  } }
}


resource "google_cloud_run_v2_service_iam_member" "permissions" {
  for_each = local.iam_flatten

  project  = var.gcp_project_id
  location = var.region_name
  name     = google_cloud_run_v2_service.service.name
  role     = each.value.role
  member   = each.value.account
}