# Local variables
locals {
  common_tags = {
    Owner       = "gowtham"
    Environment = var.environment
    Project     = "ailab"
  }
}

# VPC
resource "aws_vpc" "lab" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-ailab-${var.participant_name}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "igw-ailab-${var.participant_name}"
  }
}

# Subnets
resource "aws_subnet" "app" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-app"
  }
}

resource "aws_subnet" "db" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-db"
  }
}

# Bastion/Jump subnet (not used in our SSM-based approach but keeping structure for reference)
resource "aws_subnet" "bastion" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.3.0/27"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-bastion"
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Security Groups - NOTE: intentional security issues for Lab AI review exercise
resource "aws_security_group" "app" {
  name_prefix = "sg-app-"
  description = "Security group for app tier"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from bastion subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.3.0/27"]
  }

  ingress {
    description = "RDP from bastion subnet"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.3.0/27"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-app"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "db" {
  name_prefix = "sg-db-"
  description = "Security group for db tier"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "PostgreSQL from app subnet"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Network Interfaces
resource "aws_network_interface" "app" {
  subnet_id              = aws_subnet.app.id
  private_ips            = ["10.0.1.10"]
  security_groups        = [aws_security_group.app.id]
  source_dest_check      = true

  tags = {
    Name = "eni-app"
  }
}

resource "aws_network_interface" "db" {
  subnet_id              = aws_subnet.db.id
  private_ips            = ["10.0.2.10"]
  security_groups        = [aws_security_group.db.id]
  source_dest_check      = true

  tags = {
    Name = "eni-db"
  }
}

resource "aws_network_interface" "win" {
  subnet_id              = aws_subnet.app.id
  private_ips            = ["10.0.1.20"]
  security_groups        = [aws_security_group.app.id]
  source_dest_check      = true

  tags = {
    Name = "eni-win"
  }
}

# IAM Role for EC2 instances to use SSM Session Manager
resource "aws_iam_role" "ec2_ssm_role" {
  name_prefix = "ec2-ssm-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "ec2-profile-"
  role        = aws_iam_role.ec2_ssm_role.name
}

# EC2 Instances
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium" # equivalent to Standard_B2ms
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  network_interface_ids  = [aws_network_interface.app.id]
  monitoring             = true
  ebs_optimized          = false

  # User data for system initialization
  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e
              
              # Update system
              apt-get update
              apt-get upgrade -y
              
              # Configure SSH for password authentication
              sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
              sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
              systemctl restart sshd
              
              # Set password for labadmin user
              echo "labadmin:${var.admin_password}" | chpasswd
              EOF
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = false
  }

  tags = {
    Name        = "vm-app"
    Environment = "lab"
  }

  depends_on = [aws_internet_gateway.lab]
}

resource "aws_instance" "db" {
  ami                   = data.aws_ami.ubuntu.id
  instance_type         = "t3.medium"
  iam_instance_profile  = aws_iam_instance_profile.ec2_profile.name
  network_interface_ids = [aws_network_interface.db.id]
  monitoring            = true
  ebs_optimized         = false

  # Cloud-init for database setup
  user_data = base64encode(file("${path.module}/cloud-init-db.yaml"))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = false
  }

  tags = {
    Name        = "vm-db"
    Environment = "lab"
  }

  depends_on = [aws_internet_gateway.lab]
}

resource "aws_instance" "win" {
  ami                   = data.aws_ami.windows.id
  instance_type         = "t3.small" # equivalent to Standard_B2s
  iam_instance_profile  = aws_iam_instance_profile.ec2_profile.name
  network_interface_ids = [aws_network_interface.win.id]
  monitoring            = true
  ebs_optimized         = false

  # User data to set administrator password
  user_data = base64encode(<<-EOF
              <powershell>
              $admin = [adsi]("WinNT://./Administrator, user")
              $admin.psbase.invoke("SetPassword", "${var.admin_password}")
              
              # Enable RDP
              Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value 0
              Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
              </powershell>
              EOF
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 128
    delete_on_termination = true
    encrypted             = false
  }

  tags = {
    Name        = "vm-win"
    Environment = "lab"
  }

  depends_on = [aws_internet_gateway.lab]
}

# S3 Bucket for storage (equivalent to Azure Storage Account)
resource "aws_s3_bucket" "lab" {
  bucket_prefix = "ailab-${var.participant_name}-"

  tags = {
    Name = "s3-ailab-${var.participant_name}"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "lab" {
  bucket = aws_s3_bucket.lab.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle policy (equivalent to Azure blob retention policy)
resource "aws_s3_bucket_lifecycle_configuration" "lab" {
  bucket = aws_s3_bucket.lab.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  rule {
    id     = "delete-incomplete-multipart-uploads"
    status = "Enabled"

    incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Lambda function for automated VM shutdown (equivalent to Azure's auto-shutdown)
resource "aws_iam_role" "lambda_shutdown_role" {
  name_prefix = "lambda-shutdown-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_shutdown_policy" {
  name_prefix = "lambda-shutdown-policy-"
  role        = aws_iam_role.lambda_shutdown_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "vm_shutdown" {
  filename         = "lambda_shutdown.zip"
  function_name    = "ailab-vm-shutdown-${var.participant_name}"
  role             = aws_iam_role.lambda_shutdown_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256("lambda_shutdown.zip")

  environment {
    variables = {
      INSTANCE_IDS = "${aws_instance.app.id},${aws_instance.db.id},${aws_instance.win.id}"
      REGION       = var.aws_region
    }
  }

  tags = local.common_tags
}

# EventBridge rule for daily shutdown at 08:00 UTC
resource "aws_cloudwatch_event_rule" "vm_shutdown" {
  name_prefix            = "ailab-shutdown-"
  description            = "Trigger VM shutdown at 08:00 UTC daily"
  schedule_expression    = "cron(0 8 * * ? *)"

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "vm_shutdown" {
  rule      = aws_cloudwatch_event_rule.vm_shutdown.name
  target_id = "ShutdownLambda"
  arn       = aws_lambda_function.vm_shutdown.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vm_shutdown.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.vm_shutdown.arn
}
