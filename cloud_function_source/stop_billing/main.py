import base64
import json
import os
from google.auth import default
from googleapiclient import discovery
from googleapiclient.errors import HttpError

def stop_billing(data, context):
    """
    Cloud Function to stop billing for a project when a budget threshold is exceeded.
    """
    try:
        # Decode Pub/Sub message
        pubsub_data = base64.b64decode(data['data']).decode('utf-8')
        pubsub_json = json.loads(pubsub_data)

        print(f"Received budget alert: {pubsub_json}")

        cost_amount = pubsub_json.get('costAmount', 0.0)
        budget_amount = pubsub_json.get('budgetAmount', 0.0)

        print(f"Cost: {cost_amount}, Budget: {budget_amount}")

        if cost_amount >= budget_amount:
            project_id = os.environ.get('GCP_PROJECT')
            if not project_id:
                print("ERROR: GCP_PROJECT environment variable not set.")
                return

            print(f"Budget exceeded! Attempting to disable billing for project: {project_id}")

            # Get default credentials (should use the function's service account)
            credentials, project = default()
            print(f"Using service account from credentials: {credentials.service_account_email if hasattr(credentials, 'service_account_email') else 'Unknown'}")

            # Build the Cloud Billing API client
            billing = discovery.build(
                'cloudbilling',
                'v1',
                credentials=credentials,
                cache_discovery=False,
            )
            projects = billing.projects()

            # Check current billing status
            print(f"Checking billing info for project: {project_id}")
            billing_info = projects.getBillingInfo(
                name=f'projects/{project_id}'
            ).execute()

            print(f"Current billing info: {billing_info}")

            if billing_info.get('billingEnabled'):
                print(f'Billing is enabled. Disabling billing for project {project_id}...')
                body = {'billingAccountName': ''}  # Empty name disables billing

                result = projects.updateBillingInfo(
                    name=f'projects/{project_id}', body=body
                ).execute()

                print(f'SUCCESS: Billing disabled for project {project_id}. Result: {result}')
            else:
                print(f'INFO: Billing already disabled for project {project_id}.')
        else:
            print(f'INFO: Budget not exceeded. Current cost: {cost_amount}, Budget: {budget_amount}')

    except HttpError as e:
        print(f"HTTP Error occurred: {e}")
        print(f"Error details: {e.error_details if hasattr(e, 'error_details') else 'No additional details'}")
    except Exception as e:
        print(f"Unexpected error occurred: {e}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
