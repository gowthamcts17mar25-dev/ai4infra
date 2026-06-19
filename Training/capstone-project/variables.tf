variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
  default     = "finbridge-rg"
}

variable "vnet_name" {
  description = "Virtual network name."
  type        = string
  default     = "finbridge-vnet"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_name" {
  description = "Subnet name."
  type        = string
  default     = "finbridge-subnet"
}

variable "subnet_prefixes" {
  description = "Address prefixes for the subnet."
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "nsg_name" {
  description = "Network security group name."
  type        = string
  default     = "finbridge-nsg"
}

variable "public_ip_name" {
  description = "Public IP resource name."
  type        = string
  default     = "finbridge-pip"
}

variable "nic_name" {
  description = "Network interface name."
  type        = string
  default     = "finbridge-nic"
}

variable "vm_name" {
  description = "Virtual machine name."
  type        = string
  default     = "finbridge-vm"
}

variable "vm_size" {
  description = "VM SKU size."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Admin username for Linux VM."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key content for VM access. Leave null to use finbridge-vm-key.pub in this module folder."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.admin_ssh_public_key == null || startswith(var.admin_ssh_public_key, "ssh-")
    error_message = "admin_ssh_public_key must be null or a valid OpenSSH public key starting with 'ssh-'."
  }
}

variable "tags" {
  description = "Tags applied to all resources that support tags."
  type        = map(string)
  default = {
    workload = "linux"
    project  = "finbridge"
    managed  = "terraform"
  }
}
