locals {
  m_base_name        = var.base_name
  m_base_name_medium = format("%s--%s", local.m_base_name, local.module_name)
  module_name        = "cloudrun"
}
