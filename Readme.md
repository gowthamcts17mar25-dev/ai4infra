Generate Terraform code from scratch to deploy the following Azure resources for a Linux-based workload:
- Resource group named "finbridge-rg" in East US
- Virtual network "finbridge-vnet" with address space 10.0.0.0/16
- Subnet "finbridge-subnet" with prefix 10.0.1.0/24
- Network security group allowing inbound SSH (port 22) from any source
- Public IP and an Ubuntu Linux VM that uses key-based SSH authentication
- One tower-specific resource: Azure PostgreSQL database with basic configuration

Organize the code into main.tf, variables.tf, and outputs.tf files following best practices.
Ensure the configuration is idempotent, passes linting, and has bounded scope.

traininguser105@labasservice.onmicrosoft.com
 
5wY6L8rcUcA8l9k5

Phase 2 – Arm (Create Restore Before Fault)
Restore Script (Create First)
restore-cpu.sh
Shell#!/bin/bashecho "Stopping CPU stress processes..."pkill yespkill stresspkill stress-ngecho "CPU load removed."top -bn1 | head -15Show more lines

Test Restore Script First
Requirement says:

Restore script must be written and tested before fault.

Run:
Shellchmod +x restore-cpu.sh./restore-cpu.shShow more lines
Capture screenshot.
Add statement:
Plain TextRestore script created and successfully tested prior to fault injection.Rollback capability verified.Show more lines

Fault Injection Script
inject-cpu-fault.sh
Option 1 (Usually Available)
Shell#!/bin/bashecho "Creating CPU stress"for i in {1..4}do  yes > /dev/null &doneecho "CPU stress started"top -bn1 | head -15Show more lines

Better Option (If stress package exists)
Shell#!/bin/bashstress --cpu 4 --timeout 600Show more lines

Baseline Collection Before Fault
Create:
Shelltop -bn1 | head -15 > baseline.txtfree -m >> baseline.txtuptime >> baseline.txtShow more lines
Save this.
Very important for recovery verification.
