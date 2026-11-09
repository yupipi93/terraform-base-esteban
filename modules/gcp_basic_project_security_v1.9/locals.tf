locals {
  m_base_name = var.base_name
  # Changed to allow to remove the module_name and keep the compatibility with older module versions (2.9 for example)
  m_base_name_medium = format("%s%s%s", local.m_base_name, var.module_name != "" ? "--" : "", var.module_name)
}
