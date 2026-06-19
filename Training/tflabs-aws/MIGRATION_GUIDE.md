# Azure to AWS Terraform Migration Guide

This document maps Azure resources to their AWS equivalents in the migrated infrastructure.

## Resource Mapping

### Networking

| Azure | AWS | Terraform Resource |
|-------|-----|-------------------|
| Virtual Network (VNet) | VPC | `aws_vpc` |
| Subnet | Subnet | `aws_subnet` |
| Network Security Group (NSG) | Security Group | `aws_security_group` |
| NSG Rule | Security Group Rule | `aws_security_group_rule` (inline) |
| Network Interface (NIC) | Network Interface (ENI) | `aws_network_interface` |
| Public IP | Elastic IP / NAT Gateway | `aws_eip` / `aws_nat_gateway` |

### Compute

| Azure | AWS | Terraform Resource | Notes |
|-------|-----|-------------------|-------|
| Azure Bastion | Systems Manager Session Manager | N/A (no resource) | No VM needed |
| Linux Virtual Machine | EC2 Instance | `aws_instance` | Ubuntu 22.04 |
| Windows Virtual Machine | EC2 Instance | `aws_instance` | Windows Server 2022 |
| VM Size: Standard_B2ms | Instance Type: t3.medium | `aws_instance.instance_type` | Comparable vCPU/RAM |
| VM Size: Standard_B2s | Instance Type: t3.small | `aws_instance.instance_type` | Comparable vCPU/RAM |
| Network Interface | Network Interface | `aws_network_interface` | Attached to instances |
| Boot Diagnostics | CloudWatch | `aws_cloudwatch_log_group` | Optional |

### Storage & Databases

| Azure | AWS | Terraform Resource |
|-------|-----|-------------------|
| Storage Account | S3 Bucket | `aws_s3_bucket` |
| Blob Storage | S3 Objects | N/A (object operations) |
| Data Retention Policy | Lifecycle Policy | `aws_s3_bucket_lifecycle_configuration` |
| PostgreSQL on VM | PostgreSQL on EC2 | Cloud-init script |

### Automation & Scheduling

| Azure | AWS | Terraform Resource | Notes |
|-------|-----|-------------------|-------|
| DevTest Labs - Auto-shutdown | Lambda + EventBridge | `aws_lambda_function`, `aws_cloudwatch_event_rule` | Scheduled via cron |
| Cloud-init (custom data) | User Data / Cloud-init | `user_data` parameter | Same mechanism |

### Identity & Access Management

| Azure | AWS | Terraform Resource |
|-------|-----|-------------------|
| Managed Identity | IAM Role | `aws_iam_role` |
| Role Assignment | IAM Policy Attachment | `aws_iam_role_policy_attachment` |
| System-assigned Identity | Service Role | Implicit in `AssumeRole` |

## Configuration Mapping

### VPC & Subnet Configuration

```
Azure Setup:
├── Virtual Network: vnet-ailab (10.0.0.0/16)
├── Subnet: snet-app (10.0.1.0/24)
├── Subnet: snet-db (10.0.2.0/24)
└── Subnet: AzureBastionSubnet (10.0.3.0/27)

AWS Setup:
├── VPC: vpc-ailab-{participant} (10.0.0.0/16)
├── Subnet: subnet-app (10.0.1.0/24)
├── Subnet: subnet-db (10.0.2.0/24)
└── Subnet: subnet-bastion (10.0.3.0/27)
```

### Instance Configuration Mapping

#### Linux App VM
```hcl
# Azure
azurerm_linux_virtual_machine "app" {
  size                            = "Standard_B2ms"
  admin_username                  = "labadmin"
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [...]
  os_disk {
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
  }
}

# AWS
aws_instance "app" {
  ami              = data.aws_ami.ubuntu.id
  instance_type    = "t3.medium"
  network_interface_ids = [...]
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }
  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    # Enable password auth
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart sshd
    echo "labadmin:${var.admin_password}" | chpasswd
  EOF
}
```

#### Database VM with Cloud-init
```hcl
# Azure
azurerm_linux_virtual_machine "db" {
  custom_data = base64encode(file("${path.module}/cloud-init-db.yaml"))
  ...
}

# AWS
aws_instance "db" {
  user_data = base64encode(file("${path.module}/cloud-init-db.yaml"))
  ...
}
```

### Security Group Mapping

```hcl
# Azure NSG Rule
security_rule {
  name                       = "AllowSSH"
  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = "10.0.3.0/27"
  destination_address_prefix = "*"
}

# AWS Security Group Rule (inline)
ingress {
  description = "SSH from bastion subnet"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["10.0.3.0/27"]
}
```

### Storage Mapping

```hcl
# Azure Storage Account
azurerm_storage_account "lab" {
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

# AWS S3 Bucket
aws_s3_bucket "lab" {
  bucket_prefix = "ailab-..."
}

aws_s3_bucket_lifecycle_configuration "lab" {
  rule {
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}
```

### Auto-Shutdown Mapping

```hcl
# Azure DevTest Labs
azurerm_dev_test_global_vm_shutdown_schedule "app" {
  enabled               = true
  daily_recurrence_time = "0800"
  timezone              = "UTC"
}

# AWS Lambda + EventBridge
aws_cloudwatch_event_rule "vm_shutdown" {
  schedule_expression = "cron(0 8 * * ? *)"  # 08:00 UTC daily
}

aws_lambda_function "vm_shutdown" {
  # Stops instances at scheduled time
}
```

## Access Method Comparison

### Azure Bastion
```
User → Azure Portal/Bastion Client → Private VM (SSH/RDP)
```
- Dedicated Bastion service
- Managed by Azure
- Dedicated subnet required
- Additional cost

### AWS Systems Manager Session Manager
```
User → AWS Console/CLI → Systems Manager → Private EC2 Instance (Shell)
```
- Built-in AWS service
- No bastion VM needed
- No public IPs required
- Sessions are logged and audited
- More cost-effective

## IAM & Permissions

### Azure: Managed Identity
```hcl
resource "azurerm_linux_virtual_machine" "app" {
  # Uses system-assigned managed identity (implicit)
}
```

### AWS: IAM Role with Instance Profile
```hcl
resource "aws_iam_role" "ec2_ssm_role" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  role = aws_iam_role.ec2_ssm_role.name
}

resource "aws_instance" "app" {
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
}
```

## Naming Conventions

| Component | Azure | AWS | Terraform |
|-----------|-------|-----|-----------|
| Resource Group | rg-ailab-{participant} | (implicit) | tags |
| VNet | vnet-ailab | vpc-ailab-{participant} | `aws_vpc` |
| Subnet | snet-app/db | subnet-app/db | `aws_subnet` |
| NSG | nsg-app/db | sg-app/db | `aws_security_group` |
| NIC/ENI | nic-app/db/win | eni-app/db/win | `aws_network_interface` |
| VM | vm-app/db/win | vm-app/db/win | `aws_instance` |
| Storage | stailab{participant} | ailab-{participant}-... | `aws_s3_bucket` |

## Cost Comparison

### Azure Pricing (US East)
- Standard_B2ms: ~$35/month
- Standard_B2s: ~$24/month
- Storage Account: ~$0.50/month
- Bastion: ~$5-15/month
- **Total**: ~$65-75/month

### AWS Pricing (US East 1)
- t3.medium: ~$30/month
- t3.small: ~$18/month
- S3 (minimal usage): ~$1/month
- Lambda + EventBridge: <$1/month
- **Total**: ~$50/month

**Savings: ~25-30% with AWS**

## Key Takeaways

1. **Same Architecture**: Same CIDR blocks, subnet structure, and instance roles
2. **Different Access**: Session Manager replaces dedicated Bastion
3. **Same Data**: Cloud-init scripts work identically on both platforms
4. **Simplified Operations**: Lambda + EventBridge replaces DevTest Labs
5. **Cost Effective**: AWS setup is ~25% cheaper with equivalent functionality

## Migration Checklist

- [x] Network topology replicated (10.0.0.0/16, 3 subnets)
- [x] Security rules migrated (NSG → Security Groups)
- [x] Instance sizing equivalent (B2ms → t3.medium, B2s → t3.small)
- [x] Database initialization (cloud-init script preserved)
- [x] Storage configuration (retention policies mirrored)
- [x] Auto-shutdown scheduling (Lambda + EventBridge)
- [x] Access method modernized (Session Manager)
- [x] IAM permissions configured (SSM + Lambda roles)
- [x] Tagging strategy applied (owner, environment, project)

## Next Steps

1. Run `setup.ps1` or `setup.sh` to prepare Lambda function
2. Update `terraform.tfvars` with your values
3. Run `terraform init && terraform plan`
4. Review and apply with `terraform apply`
5. Access instances via Systems Manager Session Manager
6. Monitor costs in AWS Cost Explorer
