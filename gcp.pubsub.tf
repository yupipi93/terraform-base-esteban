# ===================================================================
# PUBSUB CONFIGURATION
# ===================================================================
# Event-driven architecture implementation following naming convention:
# {env}.{domain}.{context}.{event}

resource "google_project_service_identity" "pubsub_agent" {
  count    = length(try(local.settings.pubsub.topics, {})) > 0 ? 1 : 0
  provider = google-beta
  service  = "pubsub.googleapis.com"
  project  = local.settings.project.id
}

locals {
  # Topics read from the settings
  topic_config = try(local.settings.pubsub.topics, {})

  # Topic names built from the naming convention
  topic_names = {
    for k, v in local.topic_config : k => join(".", [
      local.workspace, # {env}
      v.domain,        # {domain}
      v.context,       # {context}
      v.event          # {event}
    ])
  }

  # Subscriptions, flattened per topic
  subscriptions = {
    for topic_key, topic in local.topic_config : topic_key => {
      for idx, sub in try(topic.subscriptions, []) : "${topic_key}-${sub.name}" => merge(
        sub,
        {
          topic_name    = local.topic_names[topic_key]
          push_endpoint = sub.type == "push" ? "${module.cloud_run_services[try(sub.service_name, sub.name)].cloudrun_service_url}${sub.endpoint}" : null
          # End of Selection
        }
      )
    }
  }

  # Dead Letter Topics
  dead_letter_topics = {
    for topic_key, topic in local.topic_config : "${topic_key}-deadletter" => {
      name           = "${local.topic_names[topic_key]}-deadletter"
      retention_days = 14 # twice the main topic's retention
    } if can(topic.subscriptions[*].dead_letter)
  }

  # Publisher and subscriber permissions per topic
  topic_permissions = {
    for topic_key, topic in local.topic_config : topic_key => {
      publishers = [
        for service in try(topic.publishers, []) : {
          service_account = "${local.base_name}-${service}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
          role            = "roles/pubsub.publisher"
        }
      ]
      subscribers = [
        for service in try(topic.subscribers, []) : {
          service_account = "${local.base_name}-${service}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
          role            = "roles/pubsub.subscriber"
        }
      ]
    }
  }
  # Names of the SERVICES that receive push subscriptions.
  oidc_service_names = distinct(flatten([
    for topic_key, topic in local.topic_config : [
      for sub in try(topic.subscriptions, []) : try(sub.service_name, sub.name)
      if sub.type == "push"
    ]
  ]))
}

# Main topics
resource "google_pubsub_topic" "topics" {
  for_each = try(local.topic_names, {})

  project = local.settings.project.id
  name    = each.value

  message_retention_duration = try(local.settings.pubsub.message_retention, "604800s") # default 7 days

  labels = merge(local.common_labels, {
    environment = local.workspace
    domain      = local.topic_config[each.key].domain
    context     = local.topic_config[each.key].context
    event       = local.topic_config[each.key].event
  })

  depends_on = [google_project_service_identity.pubsub_agent]
}

# Dead Letter Topics
resource "google_pubsub_topic" "dead_letter" {
  for_each = local.dead_letter_topics

  project = local.settings.project.id
  name    = each.value.name

  message_retention_duration = "${each.value.retention_days * 86400}s" # days to seconds

  labels = merge(local.common_labels, {
    environment = local.workspace
    type        = "dead-letter"
  })

  depends_on = [google_project_service_identity.pubsub_agent]
}
# Lets the Pub/Sub service agent sign OIDC tokens for push subscriptions
resource "google_service_account_iam_member" "pubsub_token_creator" {
  for_each = toset(local.oidc_service_names)

  service_account_id = "projects/${local.settings.project.id}/serviceAccounts/${local.base_name}-${each.value}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${try(one(google_project_service_identity.pubsub_agent[*].email), "unused@example.com")}"

  depends_on = [module.cloud_run_services]
}

# Subscriptions
resource "google_pubsub_subscription" "subscriptions" {
  for_each = merge([
    for topic_key, subs in local.subscriptions : subs
  ]...)

  project = local.settings.project.id
  name    = each.key
  topic   = google_pubsub_topic.topics[split("-", each.key)[0]].name

  ack_deadline_seconds       = try(each.value.ack_deadline_seconds, 600)
  message_retention_duration = try(local.settings.pubsub.message_retention, "604800s") # default 7 days

  labels = local.common_labels

  dynamic "push_config" {
    for_each = each.value.type == "push" ? [1] : []
    content {
      push_endpoint = each.value.push_endpoint

      attributes = {
        x-goog-version = "v1"
      }

      # OIDC authentication for the push endpoint
      oidc_token {
        service_account_email = "${local.base_name}-${try(each.value.service_name, each.value.name)}-sa@${local.settings.project.id}.iam.gserviceaccount.com"
        audience              = local.settings.pubsub.audience
      }
    }
  }

  dynamic "dead_letter_policy" {
    for_each = can(each.value.dead_letter) ? [each.value.dead_letter] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter["${split("-", each.key)[0]}-deadletter"].id
      max_delivery_attempts = dead_letter_policy.value.max_delivery_attempts
    }
  }

  retry_policy {
    minimum_backoff = try(each.value.retry_policy.minimum_backoff, "10s")
    maximum_backoff = try(each.value.retry_policy.maximum_backoff, "600s")
  }

  depends_on = [
    google_pubsub_topic.topics,
    google_pubsub_topic.dead_letter,
    google_service_account_iam_member.pubsub_token_creator
  ]
}

# IAM binding for publishers
resource "google_pubsub_topic_iam_member" "topic_publishers" {
  for_each = merge([
    for topic_key, perms in local.topic_permissions : {
      for publisher in perms.publishers : "${topic_key}-${publisher.service_account}" => {
        topic           = local.topic_names[topic_key]
        service_account = publisher.service_account
        role            = publisher.role
      }
    }
  ]...)

  project = local.settings.project.id
  topic   = each.value.topic
  role    = each.value.role
  member  = "serviceAccount:${each.value.service_account}"

  depends_on = [google_pubsub_topic.topics]
}

# IAM binding for subscribers
resource "google_pubsub_subscription_iam_member" "subscription_subscribers" {
  for_each = merge([
    for topic_key, perms in local.topic_permissions :
    {
      for pair in flatten([
        for subscriber in perms.subscribers : [
          for sub in local.topic_config[topic_key].subscriptions :
          {
            key             = "${topic_key}-${subscriber.service_account}-${sub.name}"
            subscription    = "${topic_key}-${sub.name}"
            service_account = subscriber.service_account
            role            = subscriber.role
          }
        ]
        ]) : pair.key => {
        subscription    = google_pubsub_subscription.subscriptions[pair.subscription].name
        service_account = pair.service_account
        role            = pair.role
      }
    }
  ]...)

  project      = local.settings.project.id
  subscription = each.value.subscription
  role         = each.value.role
  member       = "serviceAccount:${each.value.service_account}"

  depends_on = [google_pubsub_subscription.subscriptions]
}
