locals {
  m_base_name        = var.base_name
  m_base_name_medium = "${local.m_base_name}--${var.module_name}"
}
