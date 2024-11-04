output "resource" {
  description = "All attributes of the Virtual Machine Scale Set resource."
  value       = azurerm_orchestrated_virtual_machine_scale_set.virtual_machine_scale_set
}

output "resource_id" {
  description = "The ID of the Virtual Machine Scale Set."
  value       = azurerm_orchestrated_virtual_machine_scale_set.virtual_machine_scale_set.id
}

output "resource_name" {
  description = "The name of the Virtual Machine Scale Set."
  value       = azurerm_orchestrated_virtual_machine_scale_set.virtual_machine_scale_set.name
}

# output "autoscale_setting_id" {
#   description = "The ID of the Autoscale Setting."
#   value       = azurerm_autoscale_setting.this.id
#   condition   = length(azurerm_autoscale_setting.this) > 0
# }

output "autoscale_setting_id" {
  description = "The ID of the Autoscale Setting."
  value       = one(azurerm_monitor_autoscale_setting.this[*].id)
}
