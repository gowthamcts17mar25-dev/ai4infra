# AWS Terraform Infrastructure - AI Lab

This folder contains the AWS equivalent of the Azure infrastructure defined in the parent `tflabs` folder.

## Architecture Overview

### Comparison with Azure Setup

| Component | Azure | AWS |
|-----------|-------|-----|
| **Virtual Network** | Azure VNet (10.0.0.0/16) | AWS VPC (10.0.0.0/16) |
| **Subnets** | 3 subnets (app, db, bastion) | 3 subnets (app, db, bastion) |
| **Access Method** | Azure Bastion | AWS Systems Manager Session Manager |
| **Network Security** | Network Security Groups (NSGs) | Security Groups |
| **Compute** | 3 VMs (2 Linux, 1 Windows) | 3 EC2 instances (2 Ubuntu, 1 Windows) |
| **Database** | PostgreSQL on Linux VM | PostgreSQL on Linux EC2 (cloud-init) |
| **Storage** | Azure Storage Account | AWS S3 bucket |
| **Auto-shutdown** | Azure DevTest Labs | AWS Lambda + EventBridge |
| **Instance Access** | SSH/RDP via Bastion | Session Manager (no keys needed) |

## Key Differences from Azure

### 1. **Access Method: Systems Manager Session Manager**
- **Advantage**: No bastion host needed, no public IPs, browser-based access
- **Access**: Use AWS Console → Systems Manager → Session Manager, or CLI
- Requires: EC2 instances have IAM role with `AmazonSSMManagedInstanceCore` policy

### 2. **Auto-Shutdown Implementation**
- Uses **Lambda + EventBridge** instead of Azure DevTest Labs
- Scheduled to run daily at 08:00 UTC
- Lambda function receives instance IDs via environment variables

### 3. **Storage**
- S3 bucket replaces Azure Storage Account
- Versioning enabled for data protection
- Lifecycle policy set to delete old versions after 7 days

### 4. **Network Architecture**
- Same IP scheme (10.0.0.0/16) for compatibility
- Security groups use the same rules as NSGs
- No public IPs on instances (private subnet design)

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with credentials
3. **Terraform** v1.0+
4. **Python 3** (to create Lambda zip)

## Setup Instructions

### Step 1: Prepare Lambda Function
Before running terraform, package the Lambda function:

```bash
cd tflabs-aws

# Create zip file for Lambda function
powershell -Command "Compress-Archive -Path lambda_shutdown.py -DestinationPath lambda_shutdown.zip -Force"

# Or on Linux/macOS:
# zip lambda_shutdown.zip lambda_shutdown.py
```

### Step 2: Initialize Terraform
```bash
terraform init
```

### Step 3: Update Variables
Edit `terraform.tfvars` if needed:
- `participant_name`: Your unique identifier
- `aws_region`: AWS region (default: us-east-1)
- `admin_password`: Will be prompted via Terraform

### Step 4: Plan & Apply
```bash
# Review the plan
terraform plan

# Create resources
terraform apply
```

## Accessing the Instances

### Using AWS Systems Manager Session Manager

**Via AWS Console:**
1. Go to AWS Systems Manager → Session Manager
2. Select the instance and click "Start session"
3. You'll get a shell directly in the instance

**Via AWS CLI:**
```bash
# For Linux instances
aws ssm start-session --target <instance-id> --region us-east-1

# For Windows instances
aws ssm start-session --target <instance-id> --document-name "AWS-StartPowerShellSession" --region us-east-1
```

**Example:**
```bash
# Get instance IDs from terraform output
terraform output app_instance_id
terraform output db_instance_id

# Connect to app instance
aws ssm start-session --target <app-instance-id> --region us-east-1
```

### Password Authentication
- **Linux VMs**: Username `labadmin`, password from `admin_password` variable
- **Windows VM**: Administrator account, password from `admin_password` variable

## Outputs

After successful terraform apply, you'll see:
- `vm_app_private_ip`: Private IP of app VM
- `vm_db_private_ip`: Private IP of database VM
- `vm_win_private_ip`: Private IP of Windows VM
- `app_instance_id`: EC2 instance ID for app tier
- `db_instance_id`: EC2 instance ID for database tier
- `win_instance_id`: EC2 instance ID for Windows
- `s3_bucket_name`: S3 bucket name for storage
- `ssm_session_manager_command`: Example command to connect

## Database Access

### From App VM to Database VM
```bash
# From app instance
psql -h 10.0.2.10 -U postgres -d postgres
```

### From Local Machine
The database is not publicly accessible (no public IP). To access:
1. Connect to app VM via Session Manager
2. Use `psql` command to connect to database VM

## Cost Considerations

**Estimated Monthly Cost (us-east-1, on-demand):**
- 2x t3.medium (app + db): ~$30
- 1x t3.small (Windows): ~$18
- S3 bucket (minimal): ~$1
- Lambda + EventBridge: <$1
- **Total**: ~$50/month

## Cleaning Up

To delete all resources:
```bash
terraform destroy
```

## Important Notes

### Security Warnings
The security groups intentionally have:
- SSH/RDP allowed from bastion subnet (for lab purposes)
- PostgreSQL open from app subnet

These should be tightened in production. This mirrors the "intentional security issues for Lab AI review exercise" from the Azure setup.

### IAM Permissions Required
The AWS credentials used must have permissions for:
- EC2 (VPC, security groups, instances)
- S3 (bucket creation)
- Lambda (function creation)
- IAM (role creation)
- CloudWatch (event rules)

### Regional Considerations
- Change `aws_region` variable to deploy to a different region
- Availability zone is auto-selected from the chosen region

## Files

- `providers.tf`: AWS provider configuration
- `variables.tf`: Input variables and data sources for AMI lookup
- `main.tf`: VPC, subnets, security groups, EC2 instances, S3, Lambda
- `output.tf`: Terraform outputs
- `terraform.tfvars`: Variable values (customize as needed)
- `cloud-init-db.yaml`: Cloud-init script for database VM
- `lambda_shutdown.py`: Lambda function source code
- `lambda_shutdown.zip`: Packaged Lambda function (created during setup)

## Troubleshooting

### Lambda zip file not found
Solution: Run the zip command in Step 1 before `terraform apply`

### Instances not accessible via Session Manager
Check:
1. Instance has IAM instance profile with `AmazonSSMManagedInstanceCore`
2. Instance has network connectivity
3. AWS Systems Manager agent is running (should auto-start)

### Password authentication not working
Ensure `admin_password` variable is set and instances are fully booted (wait 2-3 minutes after creation)

## Migration from Azure

All resources use the same naming convention and network topology as the Azure setup for easy comparison:
- Same CIDR blocks (10.0.0.0/16)
- Same subnet structure (app: 10.0.1.0/24, db: 10.0.2.0/24)
- Same VM sizing (B2ms → t3.medium, B2s → t3.small)
- Same storage retention policies (7-day versioning)
- Same shutdown schedule (08:00 UTC daily)
