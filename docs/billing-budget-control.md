# Billing budget and the optional billing shutdown

A `budget` section creates a Cloud Billing budget for the project, with email
alerts at the thresholds you list. With `enable_auto_stop: true` it also deploys a
Cloud Function that disables billing on the project once the spend reaches the
budget. That stops every billable service in it, so it is off unless asked for,
and the reference workspaces (`dev`, `stg`, `pre`, `pro`) keep it off.

## Configuration

`gcp.billing.tf` reads the `budget` section of `settings/<workspace>.yaml`:

```yaml
budget:
  billing_account: "000000-000000-000000"
  amount: 100
  alert_spent_percents:
    - 0.5
    - 0.9
    - 1.0
  enable_auto_stop: false  # true deploys the function that disables billing
```

| Key | What it does |
|---|---|
| `billing_account` | The billing account that pays for the project. Without it no budget is created. |
| `amount` | The monthly limit, in EUR: the currency is fixed in `gcp.billing.tf`, and Cloud Billing refuses a budget whose currency differs from the billing account's. |
| `alert_spent_percents` | One alert rule per entry, on the current spend (`0.9` is 90 %). |
| `enable_auto_stop` | Default `false`. `true` deploys the shutdown described below. |

The budget watches this project only. The alerts go to the billing account's
budget recipients (billing administrators and users by default), not to
`security.alerts_email`.

## How the shutdown works

```
┌─────────────────────┐    ┌─────────────────────────────┐    ┌──────────────────────────┐
│  Cloud Billing      │    │  Pub/Sub topic              │    │  Cloud Function (gen 2)  │
│  budget             │───▶│  <client>-budget-           │───▶│  <client>-stop-billing   │
│                     │    │  notifications              │    │                          │
└─────────────────────┘    └─────────────────────────────┘    └────────────┬─────────────┘
                                                                           │
                                                                           ▼
                                                              ┌──────────────────────────┐
                                                              │  Cloud Billing API:      │
                                                              │  unlink the project      │
                                                              └──────────────────────────┘
```

With `enable_auto_stop: true` the stack adds:

- a Pub/Sub topic `<client.name>-budget-notifications`, set as the budget's
  programmatic notification target. Cloud Billing publishes the budget status
  to it several times a day, not only when a threshold is crossed;
- a bucket `<client.name>-<workspace>-stop-billing-code` with the zipped source
  of `cloud_function_source/stop_billing/`;
- the function `<client.name>-stop-billing` (Python 3.13, one instance at most),
  triggered by each message on the topic;
- its service account `<client.name>-stop-billing-sa`, with
  `roles/billing.projectManager`, `roles/serviceusage.serviceUsageConsumer` and
  `roles/cloudfunctions.developer` on the project.

The function reads `costAmount` and `budgetAmount` from the message. When the
cost is at or above the budget and billing is still on, it calls the Cloud
Billing API with an empty billing account, which unlinks the project:

```python
if cost_amount >= budget_amount:
    # projects.updateBillingInfo(name=f"projects/{project_id}", body={"billingAccountName": ""})
```

Below the budget it logs the figures and does nothing. Thresholds under 100 %
only send the usual alerts.

## What happens when it fires

Billing off stops the project's paid resources: Cloud Run, Cloud SQL, Redis and
the load balancer stop serving, and Google may delete resources of a project
that stays without billing.

To recover:

1. Find out why the spend grew, and raise `budget.amount` if the limit was too
   low (or turn `enable_auto_stop` off).
2. Link the billing account again. It needs billing permissions on the account
   (`roles/billing.user` or more) and on the project:

   ```bash
   gcloud billing projects link <project-id> --billing-account=<billing-account-id>
   ```

3. Wait for the services to come back; that can take a few minutes.

To stop the function from acting without a Terraform change, remove its role:

```bash
gcloud projects remove-iam-policy-binding <project-id> \
  --member="serviceAccount:<client.name>-stop-billing-sa@<project-id>.iam.gserviceaccount.com" \
  --role="roles/billing.projectManager"
```

The next apply grants it again; set `enable_auto_stop: false` to make it stick.

## Testing

Publish a message to the topic by hand. Below the budget nothing happens:

```bash
gcloud pubsub topics publish <client.name>-budget-notifications \
  --project=<project-id> \
  --message='{"costAmount": 50.0, "budgetAmount": 100.0, "alertThresholdExceeded": 0.5}'
```

The function logs that the budget is not exceeded. A message with
`costAmount` at or above `budgetAmount` really disables billing on the project:
only send it to a project you can afford to stop.
