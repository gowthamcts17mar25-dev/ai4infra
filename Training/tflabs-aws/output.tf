output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.lab.id
}

output "vm_app_private_ip" {
  description = "Private IP of app VM"
  value       = aws_instance.app.private_ip
}

output "vm_db_private_ip" {
  description = "Private IP of db VM"
  value       = aws_instance.db.private_ip
}

output "vm_win_private_ip" {
  description = "Private IP of Windows VM"
  value       = aws_instance.win.private_ip
}

output "app_instance_id" {
  description = "Instance ID of app VM"
  value       = aws_instance.app.id
}

output "db_instance_id" {
  description = "Instance ID of db VM"
  value       = aws_instance.db.id
}

output "win_instance_id" {
  description = "Instance ID of Windows VM"
  value       = aws_instance.win.id
}

output "s3_bucket_name" {
  description = "S3 bucket name for storage"
  value       = aws_s3_bucket.lab.id
}

output "app_subnet_id" {
  description = "App subnet ID"
  value       = aws_subnet.app.id
}

output "db_subnet_id" {
  description = "DB subnet ID"
  value       = aws_subnet.db.id
}

output "ssm_session_manager_command" {
  description = "Command to connect to instance using Session Manager"
  value       = "aws ssm start-session --target <instance-id> --region ${var.aws_region}"
}

output "ssm_connection_info" {
  description = "How to connect to instances using AWS Systems Manager Session Manager"
  value       = "Use AWS Systems Manager Session Manager in AWS Console or CLI to connect to instances. No SSH key or Bastion host required."
}
