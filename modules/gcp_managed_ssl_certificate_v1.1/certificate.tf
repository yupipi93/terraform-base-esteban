resource "random_id" "base" {
  keepers = {
    domains = md5(tostring(jsonencode(var.domain)))
  }

  byte_length = 2
}

resource "google_compute_managed_ssl_certificate" "base" {

  project = var.gcp_project_id
  name    = format("%s--%s", local.m_base_name, random_id.base.hex)

  managed {
    domains = flatten(var.domain)
  }

  lifecycle {
    create_before_destroy = true
  }

}
