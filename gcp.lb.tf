# ===================================================================
# LOAD BALANCER CONFIGURATION LOCALS
# ===================================================================

locals {
  # Check if LB and monitoring configuration exists in settings
  lb_enabled    = can(local.settings.lb)
  lb_monitoring = can(local.settings.monitoring.lb)

  # TLS policy of the HTTPS proxy, from lb.ssl_policy. MODERN with TLS 1.2 by default.
  lb_ssl_policy = {
    profile         = try(local.settings.lb.ssl_policy.profile, "MODERN")
    min_tls_version = try(local.settings.lb.ssl_policy.min_tls_version, "TLS_1_2")
    custom_features = try(local.settings.lb.ssl_policy.custom_features, [])
  }
}

# ===================================================================
# IAP CONFIGURATION LOCALS
# ===================================================================
# Extract IAP-enabled rules for separate backend services
locals {
  # Get all rules that have IAP enabled
  iap_rules = flatten([
    for service_key, service_config in local.app_services : [
      for rule_index, rule in try(service_config.loadbalancer.rules, []) : {
        service_key = service_key
        rule_index  = rule_index
        path        = rule.path
        rewrite     = try(rule.rewrite, "/")
        rule_id     = "${service_key}-admin-rule-${rule_index}"
        iap_config = merge(
          rule.iap,
          {
            # Use centralized members if use_default_members is true, otherwise use rule-specific members
            members = try(rule.iap.use_default_members, false) == true ? try(local.settings.iap.admin_access.members, []) : try(rule.iap.members, [])
          }
        )
        backend_name = "${service_key}-admin"
      } if try(rule.iap.enabled, false) == true
    ] if length(try(service_config.loadbalancer.rules, [])) > 0
  ])

  # Convert to map for for_each
  iap_rules_map = { for rule in local.iap_rules : rule.rule_id => rule }
}

# ===================================================================
# LOAD BALANCER CONFIGURATION
# ===================================================================

# URL Map with path-based routing
resource "google_compute_url_map" "load_balancer" {
  count = local.lb_enabled ? 1 : 0

  name            = "${local.base_name_medium}-lb-v2"
  default_service = google_compute_backend_service.default_backend[0].self_link

  # Add explicit dependency
  depends_on = [
    google_compute_backend_service.service_backend,
    google_compute_backend_service.default_backend,
    google_compute_backend_service.iap_backend
  ]

  # Main path matcher with advanced URL rewriting (enabled by EXTERNAL_MANAGED)
  path_matcher {
    name            = "main-matcher"
    default_service = google_compute_backend_service.default_backend[0].self_link

    # IAP-ENABLED RULES - Must come FIRST to match more specific admin paths
    dynamic "path_rule" {
      for_each = local.iap_rules_map

      content {
        paths = [path_rule.value.path]
        route_action {
          url_rewrite {
            path_prefix_rewrite = path_rule.value.rewrite
          }
          weighted_backend_services {
            backend_service = google_compute_backend_service.iap_backend[path_rule.key].self_link
            weight          = 100
          }
        }
      }
    }

    # REGULAR RULES - Advanced URL rewriting with route_action (EXTERNAL_MANAGED enabled)
    # Exclude IAP-enabled rules (they are handled by the IAP backend services above)
    dynamic "path_rule" {
      # Flatten the rules structure: for each service, create entries for each rule
      for_each = flatten([
        for service_key, service_config in local.app_services : [
          for rule_index, rule in try(service_config.loadbalancer.rules, []) : {
            service_key = service_key
            rule_index  = rule_index
            path        = rule.path
            rewrite     = try(rule.rewrite, "/") # URL rewrite path
            rule_id     = "${service_key}-rule-${rule_index}"
          } if try(rule.iap.enabled, false) == false # Exclude IAP-enabled rules
        ] if length(try(service_config.loadbalancer.rules, [])) > 0
      ])

      content {
        paths = [path_rule.value.path]
        route_action {
          url_rewrite {
            path_prefix_rewrite = path_rule.value.rewrite
          }
          weighted_backend_services {
            backend_service = google_compute_backend_service.service_backend[path_rule.value.service_key].self_link
            weight          = 100
          }
        }
      }
    }

    # Backward compatibility: Handle services still using legacy 'paths' configuration
    dynamic "path_rule" {
      for_each = {
        for k, v in local.app_services : k => v
        if length(try(v.loadbalancer.paths, [])) > 0 && length(try(v.loadbalancer.rules, [])) == 0
      }

      content {
        paths   = try(path_rule.value.loadbalancer.paths, [])
        service = google_compute_backend_service.service_backend[path_rule.key].id
      }
    }
  }

  # Single host rule for all traffic
  host_rule {
    hosts        = try(local.settings.lb.domain, [])
    path_matcher = "main-matcher"
  }

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true
  }
}


# Default backend service (404 handler) - EXTERNAL MANAGED
resource "google_compute_backend_service" "default_backend" {
  count = local.lb_enabled ? 1 : 0

  name                  = "${local.base_name_medium}-default-backend-v2"
  port_name             = "http"
  protocol              = "HTTP"
  timeout_sec           = try(local.settings.lb.timeout_sec, 30)
  load_balancing_scheme = "EXTERNAL_MANAGED" # Match the other backend services
  locality_lb_policy    = "ROUND_ROBIN"      # Required for EXTERNAL_MANAGED migration

  security_policy = google_compute_security_policy.cloud_armor_waf[0].self_link

  # Enable logging for debugging and monitoring
  log_config {
    enable      = true
    sample_rate = 1.0 # 100% of requests logged
  }

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true
  }
}


# Static IP for Load Balancer
resource "google_compute_global_address" "lb_static_ip" {
  count = local.lb_enabled ? 1 : 0

  name = "${local.base_name_medium}-lb-ip"

  labels = local.common_labels
}

# Managed SSL Certificate
module "certificate_main" {
  count = local.lb_enabled ? 1 : 0

  source         = "./modules/gcp_managed_ssl_certificate_v1.1"
  base_name      = format("%s--%s-main", local.base_name, local.workspace)
  region_name    = local.settings.region_name
  gcp_project_id = local.settings.project.id
  domain         = try(local.settings.lb.domain, [])
}

# SSL Policy for secure HTTPS connections
resource "google_compute_ssl_policy" "lb_ssl_policy" {
  count = local.lb_enabled ? 1 : 0

  name            = "${local.base_name_medium}-ssl-policy"
  profile         = local.lb_ssl_policy.profile
  min_tls_version = local.lb_ssl_policy.min_tls_version
  custom_features = local.lb_ssl_policy.profile == "CUSTOM" ? local.lb_ssl_policy.custom_features : null

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = contains(["COMPATIBLE", "MODERN", "RESTRICTED", "CUSTOM"], local.lb_ssl_policy.profile)
      error_message = "lb.ssl_policy.profile must be COMPATIBLE, MODERN, RESTRICTED or CUSTOM."
    }

    precondition {
      condition     = contains(["TLS_1_0", "TLS_1_1", "TLS_1_2", "TLS_1_3"], local.lb_ssl_policy.min_tls_version)
      error_message = "lb.ssl_policy.min_tls_version must be TLS_1_0, TLS_1_1, TLS_1_2 or TLS_1_3."
    }

    precondition {
      condition     = local.lb_ssl_policy.min_tls_version != "TLS_1_3" || local.lb_ssl_policy.profile == "RESTRICTED"
      error_message = "lb.ssl_policy.min_tls_version TLS_1_3 needs profile RESTRICTED."
    }

    precondition {
      condition     = (local.lb_ssl_policy.profile == "CUSTOM") == (length(local.lb_ssl_policy.custom_features) > 0)
      error_message = "lb.ssl_policy.custom_features is required with profile CUSTOM and not allowed with any other profile."
    }
  }
}


# Network Endpoint Groups (NEGs) for each Cloud Run service
resource "google_compute_region_network_endpoint_group" "service_neg" {
  for_each = local.lb_enabled ? {
    for k, v in local.app_services : k => v
    if length(try(v.loadbalancer.rules, try(v.loadbalancer.paths, []))) > 0
  } : {}

  name                  = format("%s-%s-neg", local.base_name_medium, try(each.value.name, each.key))
  network_endpoint_type = "SERVERLESS"
  region                = local.settings.region_name

  cloud_run {
    service = format("%s-%s", local.base_name, try(each.value.name, each.key))
  }

  depends_on = [module.cloud_run_services]

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true
  }
}

# Health Checks are not supported for Cloud Run services with serverless NEGs
# Cloud Run handles health checks internally through the platform
# External health checks would conflict with Cloud Run's internal health management

# Backend Services for each Cloud Run service (EXTERNAL MANAGED)
resource "google_compute_backend_service" "service_backend" {
  for_each = local.lb_enabled ? {
    for k, v in local.app_services : k => v
    if length(try(v.loadbalancer.rules, try(v.loadbalancer.paths, []))) > 0
  } : {}

  name                  = format("%s-%s-backend-v2", local.base_name_medium, try(each.value.name, each.key))
  port_name             = "http"
  protocol              = "HTTP"
  timeout_sec           = try(local.settings.lb.timeout_sec, 30)
  load_balancing_scheme = "EXTERNAL_MANAGED" # Enable advanced features like URL rewriting
  locality_lb_policy    = "ROUND_ROBIN"      # Required for EXTERNAL_MANAGED migration
  security_policy       = google_compute_security_policy.cloud_armor_waf[0].self_link

  backend {
    group = google_compute_region_network_endpoint_group.service_neg[each.key].id
  }

  # Enable logging for debugging and monitoring
  log_config {
    enable      = true
    sample_rate = 1.0 # 100% of requests logged
  }

  # Cloud Run services handle health checks internally
  # External health checks are not supported with serverless NEGs

  # Explicit dependency to ensure proper destruction order
  depends_on = [
    google_compute_region_network_endpoint_group.service_neg
  ]

  # Add lifecycle rule to handle dependencies
  lifecycle {
    create_before_destroy = true
  }
}



# HTTPS Proxy
resource "google_compute_target_https_proxy" "lb_https_proxy" {
  count = local.lb_enabled ? 1 : 0

  name    = "${local.base_name_medium}-https-proxy-v2"
  url_map = google_compute_url_map.load_balancer[0].id

  ssl_certificates = [
    module.certificate_main[0].id
  ]

  # Apply SSL policy for secure TLS configuration
  ssl_policy = google_compute_ssl_policy.lb_ssl_policy[0].id


  # Explicit dependency to ensure proper destruction order
  depends_on = [
    google_compute_url_map.load_balancer,
    module.certificate_main,
    google_compute_ssl_policy.lb_ssl_policy
  ]

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true
  }
}

# Global Forwarding Rule
resource "google_compute_global_forwarding_rule" "lb_forwarding_rule" {
  count = local.lb_enabled ? 1 : 0

  name                  = "${local.base_name_medium}-forwarding-rule-v2"
  target                = google_compute_target_https_proxy.lb_https_proxy[0].id
  port_range            = "443"
  ip_address            = google_compute_global_address.lb_static_ip[0].address
  load_balancing_scheme = "EXTERNAL_MANAGED"

  labels = local.common_labels

  # Explicit dependency to ensure proper destruction order
  depends_on = [
    google_compute_target_https_proxy.lb_https_proxy,
    google_compute_global_address.lb_static_ip
  ]

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true
  }
}

# HTTP to HTTPS redirect
resource "google_compute_url_map" "lb_http_redirect" {
  count = local.lb_enabled ? 1 : 0

  name = "${local.base_name_medium}-http-redirect-v2"

  default_url_redirect {
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
    https_redirect         = true
  }

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_target_http_proxy" "lb_http_proxy" {
  count = local.lb_enabled ? 1 : 0

  name    = "${local.base_name_medium}-http-proxy-v2"
  url_map = google_compute_url_map.lb_http_redirect[0].id

  # Explicit dependency to ensure proper destruction order
  depends_on = [
    google_compute_url_map.lb_http_redirect
  ]

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_global_forwarding_rule" "lb_http_forwarding_rule" {
  count = local.lb_enabled ? 1 : 0

  name                  = "${local.base_name_medium}-http-forwarding-rule-v2"
  target                = google_compute_target_http_proxy.lb_http_proxy[0].id
  port_range            = "80"
  ip_address            = google_compute_global_address.lb_static_ip[0].address
  load_balancing_scheme = "EXTERNAL_MANAGED"

  labels = local.common_labels

  # Explicit dependency to ensure proper destruction order
  depends_on = [
    google_compute_target_http_proxy.lb_http_proxy,
    google_compute_global_address.lb_static_ip
  ]

  # Lifecycle rule to prevent premature destruction
  lifecycle {
    create_before_destroy = true
  }
}

# Load Balancer Monitoring
module "monitoring_load_balancing" {
  count = local.lb_enabled && local.lb_monitoring ? 1 : 0

  source = "./modules/gcp_monitoring_lb_v2.6"

  gcp_project_id            = local.settings.project.id
  gcp_project_id_monitoring = local.settings.project.id
  region_name               = local.settings.region_name
  load_balancer             = google_compute_url_map.load_balancer[0].name
  repo_iac                  = local.settings.iac.repo

  # One policy per key set under monitoring.lb, each with every field of the
  # module variable (duration, threshold_value, alignment_period, severity,
  # enabled). All of them notify the security alerts channel.

  latency = can(local.settings.monitoring.lb.latency) ? {
    "main" = merge(
      local.settings.monitoring.lb.latency,
      {
        notification_channels = [google_monitoring_notification_channel.security_alerts.id]
      }
    )
  } : {}

  request_count = can(local.settings.monitoring.lb.request_count) ? {
    "main" = merge(
      local.settings.monitoring.lb.request_count,
      {
        notification_channels = [google_monitoring_notification_channel.security_alerts.id]
      }
    )
  } : {}

  status_403_cloud_armor = can(local.settings.monitoring.lb.status_403_cloud_armor) ? {
    "main" = merge(
      local.settings.monitoring.lb.status_403_cloud_armor,
      {
        notification_channels = [google_monitoring_notification_channel.security_alerts.id]
      }
    )
  } : {}

  status_403_backends = can(local.settings.monitoring.lb.status_403_backends) ? {
    "main" = merge(
      local.settings.monitoring.lb.status_403_backends,
      {
        notification_channels = [google_monitoring_notification_channel.security_alerts.id]
      }
    )
  } : {}

  status_404_backends = can(local.settings.monitoring.lb.status_404_backends) ? {
    "main" = merge(
      local.settings.monitoring.lb.status_404_backends,
      {
        ignore_backends       = []
        notification_channels = [google_monitoring_notification_channel.security_alerts.id]
      }
    )
  } : {}

  status_4xx_backends = can(local.settings.monitoring.lb.status_4xx_backends) ? {
    "main" = merge(
      local.settings.monitoring.lb.status_4xx_backends,
      {
        ignore_backends       = []
        notification_channels = [google_monitoring_notification_channel.security_alerts.id]
      }
    )
  } : {}

  status_5xx_backends = can(local.settings.monitoring.lb.status_5xx_backends) ? {
    "main" = merge(
      local.settings.monitoring.lb.status_5xx_backends,
      {
        ignore_backends       = []
        notification_channels = [google_monitoring_notification_channel.security_alerts.id]
      }
    )
  } : {}
}

# ===================================================================
# IAP RESOURCES
# ===================================================================

# ===================================================================
# IAP OAuth Setup - Manual Configuration Required
# ===================================================================
# Note: Google deprecated the IAP OAuth Admin API as of July 2025
# You must manually create the OAuth consent screen in Google Cloud Console:
# 1. Go to: https://console.cloud.google.com/apis/credentials/consent
# 2. Set up OAuth consent screen (External user type recommended)
# 3. Google will automatically provide managed OAuth clients for IAP

# IAP-Protected Backend Services
resource "google_compute_backend_service" "iap_backend" {
  for_each = local.lb_enabled ? local.iap_rules_map : {}

  name                  = format("%s-%s-backend-iap", local.base_name_medium, each.value.backend_name)
  port_name             = "http"
  protocol              = "HTTP"
  timeout_sec           = try(local.settings.lb.timeout_sec, 30)
  load_balancing_scheme = "EXTERNAL_MANAGED"
  locality_lb_policy    = "ROUND_ROBIN"
  security_policy       = google_compute_security_policy.cloud_armor_waf[0].self_link

  backend {
    group = google_compute_region_network_endpoint_group.service_neg[each.value.service_key].id
  }

  # Enable logging for debugging and monitoring
  log_config {
    enable      = true
    sample_rate = 1.0 # 100% of requests logged
  }

  # Enable IAP with Google-managed OAuth client
  # No explicit oauth2_client_id/secret needed - Google manages this automatically
  iap {
    enabled = true
  }

  depends_on = [
    google_compute_region_network_endpoint_group.service_neg
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ===================================================================
# CONSOLIDATED IAP IAM BINDINGS
# ===================================================================
# Create a single project-level IAP binding with all unique members
# This prevents conflicts from multiple binding resources targeting the same resource

locals {
  # Collect all unique IAP members from all rules to avoid duplicates
  all_iap_members = toset(flatten([
    for rule in local.iap_rules_map : rule.iap_config.members
  ]))
}

# Single consolidated IAP binding for all IAP-protected services
resource "google_iap_web_iam_binding" "iap_resource_accessor" {
  count = local.lb_enabled && length(local.all_iap_members) > 0 ? 1 : 0

  project = local.settings.project.id
  role    = "roles/iap.httpsResourceAccessor"
  members = local.all_iap_members

  # IAP web backend service binding
  depends_on = [google_compute_backend_service.iap_backend]

  # Lifecycle management
  lifecycle {
    create_before_destroy = true
  }
}
