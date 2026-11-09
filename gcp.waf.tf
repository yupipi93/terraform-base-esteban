
# ===================================================================
# CLOUD ARMOR WAF SECURITY POLICY
# ===================================================================
# Web Application Firewall (WAF) security policy for load balancer protection
resource "google_compute_security_policy" "cloud_armor_waf" {
  count = local.lb_enabled ? 1 : 0

  name        = "${local.base_name_medium}-waf-policy"
  description = "Cloud Armor WAF policy for ${local.base_name} load balancer"
  project     = local.settings.project.id

  # Default rule - allow all traffic (lowest priority)
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default rule - allow all traffic"
  }

  # OWASP Top 10 Protection Rules
  # SQL Injection protection
  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable')"
      }
    }
    description = "SQL injection protection (OWASP)"
  }

  # Cross-site scripting (XSS) protection
  rule {
    action   = "deny(403)"
    priority = "1001"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "XSS protection (OWASP)"
  }

  # Local file inclusion (LFI) protection
  rule {
    action   = "deny(403)"
    priority = "1002"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-v33-stable')"
      }
    }
    description = "Local file inclusion protection (OWASP)"
  }

  # Remote file inclusion (RFI) protection
  rule {
    action   = "deny(403)"
    priority = "1003"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rfi-v33-stable')"
      }
    }
    description = "Remote file inclusion protection (OWASP)"
  }

  # Remote code execution (RCE) protection
  rule {
    action   = "deny(403)"
    priority = "1004"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-v33-stable')"
      }
    }
    description = "Remote code execution protection (OWASP)"
  }

  # Method enforcement protection
  rule {
    action   = "deny(403)"
    priority = "1005"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('methodenforcement-v33-stable')"
      }
    }
    description = "Method enforcement protection (OWASP)"
  }

  # Scanner detection protection
  rule {
    action   = "deny(403)"
    priority = "1006"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('scannerdetection-v33-stable')"
      }
    }
    description = "Scanner detection protection (OWASP)"
  }

  # Protocol attack protection
  rule {
    action   = "deny(403)"
    priority = "1007"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('protocolattack-v33-stable')"
      }
    }
    description = "Protocol attack protection (OWASP)"
  }

  # PHP injection protection
  rule {
    action   = "deny(403)"
    priority = "1008"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('php-v33-stable')"
      }
    }
    description = "PHP injection protection (OWASP)"
  }

  # Session fixation protection
  rule {
    action   = "deny(403)"
    priority = "1009"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sessionfixation-v33-stable')"
      }
    }
    description = "Session fixation protection (OWASP)"
  }

  # Adaptive protection settings
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}
