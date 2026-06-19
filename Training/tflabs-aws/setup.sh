#!/bin/bash
# Setup script for AWS Terraform infrastructure
# Run this script before terraform apply

set -e

echo "=== AWS AI Lab Terraform Setup ==="
echo ""

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed. Please install Python 3."
    exit 1
fi

echo "✓ Python 3 found"

# Check if zip is available
if ! command -v zip &> /dev/null; then
    echo "WARNING: zip command not found. Using Python to create zip file instead."
    python3 -c "
import zipfile
with zipfile.ZipFile('lambda_shutdown.zip', 'w') as zf:
    zf.write('lambda_shutdown.py')
print('✓ Created lambda_shutdown.zip')
"
else
    echo "✓ Creating lambda_shutdown.zip"
    zip -j lambda_shutdown.zip lambda_shutdown.py
fi

echo ""
echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Review terraform.tfvars and update values if needed"
echo "2. Run: terraform init"
echo "3. Run: terraform plan"
echo "4. Run: terraform apply"
echo ""
