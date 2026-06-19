output "resource_group_name" {
  description = "Name of the deployed resource group."
  value       = azurerm_resource_group.rg.name
}

output "vm_public_ip" {
  description = "Public IPv4 address of the Linux VM."
  value       = azurerm_public_ip.pip.ip_address
}

output "vm_id" {
  description = "Resource ID of the Linux VM."
  value       = azurerm_linux_virtual_machine.vm.id
}


