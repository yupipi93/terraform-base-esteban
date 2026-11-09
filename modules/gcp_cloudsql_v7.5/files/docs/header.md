# Module requirements

From version v5.5 and above, you need to update the Google Cloud Provider to >=4.75.0

From version v7.5, `backup_configuration` takes `point_in_time_recovery_enabled` and
`transaction_log_retention_days`. MySQL gets point-in-time recovery from the binary log,
PostgreSQL and SQL Server from `point_in_time_recovery_enabled`. Leaving
`point_in_time_recovery_enabled` unset keeps the v7.4 behaviour (MySQL follows
`dbe.binary_log_enabled`, other engines off).
