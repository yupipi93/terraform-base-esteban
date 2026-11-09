locals {
  iam_permissions = flatten([
    for permission_data in var.permissions : [
      for item in setproduct(permission_data.members, permission_data.roles) : {
        "member" = item[0],
        "role"   = item[1]
      }
    ]
  ])
}

resource "google_project_iam_member" "permissions" {
  count   = length(local.iam_permissions)
  project = var.project_id
  member  = local.iam_permissions[count.index].member
  role    = local.iam_permissions[count.index].role
}