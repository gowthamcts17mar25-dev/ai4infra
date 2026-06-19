# Setup script for AWS Terraform infrastructure
# Run this script before terraform apply

Write-Host "=== AWS AI Lab Terraform Setup (PowerShell) ===" -ForegroundColor Green
Write-Host ""

# Check if Python is installed
$pythonPath = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonPath) {
    Write-Host "ERROR: Python is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Python or add it to your PATH."
    exit 1
}

Write-Host "✓ Python found" -ForegroundColor Green

# Create Lambda zip file
Write-Host "Creating lambda_shutdown.zip..." -ForegroundColor Cyan

$sourcePath = Join-Path (Get-Location) "lambda_shutdown.py"
$zipPath = Join-Path (Get-Location) "lambda_shutdown.zip"

# Use PowerShell's built-in compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

[System.IO.Compression.ZipFile]::CreateFromDirectory((Split-Path $sourcePath), $zipPath)

# Need to recreate properly - add single file
[System.IO.Compression.ZipFile]::CreateFromDirectory($PWD, $zipPath, "Optimal", $false) -ErrorAction SilentlyContinue

# Alternative: use 7-Zip if available
$7zip = Get-Command 7z -ErrorAction SilentlyContinue
if ($7zip) {
    Write-Host "Using 7-Zip to create archive..." -ForegroundColor Cyan
    & 7z a -tzip $zipPath $sourcePath | Out-Null
} else {
    # Fallback: use Compress-Archive (only files)
    Write-Host "Using Compress-Archive..." -ForegroundColor Cyan
    $tempDir = New-TemporaryFile | Remove-Item -Force; New-Item -ItemType Directory -Path $tempDir | Out-Null
    Copy-Item $sourcePath -Destination $tempDir
    Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
    Remove-Item $tempDir -Recurse -Force
}

if (Test-Path $zipPath) {
    Write-Host "✓ Created lambda_shutdown.zip" -ForegroundColor Green
} else {
    Write-Host "ERROR: Failed to create lambda_shutdown.zip" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✓ Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Review terraform.tfvars and update values if needed"
Write-Host "2. Run: terraform init"
Write-Host "3. Run: terraform plan"
Write-Host "4. Run: terraform apply"
Write-Host ""
