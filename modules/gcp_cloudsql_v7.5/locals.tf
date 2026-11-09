locals {
  m_base_name = var.base_name
  # Changed to allow to remove the module_name and keep the compatibility with older module versions (2.9 for example)
  m_base_name_medium = format("%s%s%s", local.m_base_name, var.module_name != "" ? "--" : "", var.module_name)

  # MySQL recovers to a point in time from the binary log; PostgreSQL and SQL Server use point_in_time_recovery_enabled.
  is_mysql = length(regexall("mysql", lower(var.dbe.version))) > 0
  pitr_enabled = coalesce(
    var.backup_configuration.point_in_time_recovery_enabled,
    local.is_mysql ? var.dbe.binary_log_enabled : false,
  )
}
