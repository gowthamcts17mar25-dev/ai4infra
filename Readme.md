Generate Terraform code from scratch to deploy the following Azure resources for a Linux-based workload:
- Resource group named "finbridge-rg" in East US
- Virtual network "finbridge-vnet" with address space 10.0.0.0/16
- Subnet "finbridge-subnet" with prefix 10.0.1.0/24
- Network security group allowing inbound SSH (port 22) from any source
- Public IP and an Ubuntu Linux VM that uses key-based SSH authentication
- One tower-specific resource: Azure PostgreSQL database with basic configuration

Organize the code into main.tf, variables.tf, and outputs.tf files following best practices.
Ensure the configuration is idempotent, passes linting, and has bounded scope.
