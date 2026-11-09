## Breaking changes

Since 27/10/2023 you need to add the var service_account.name by hand, matching the name of the already created account, to be backwards compatible.

Since 21/11/2023 the module uses the google_cloud_run_v2_service resource, so old versions of the module are not compatible anymore. The same options are available, so the only problem is that the cloudrun will be recreated.
