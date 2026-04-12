# =============================================================================
# Vaultwarden Cloud Backup Script
# Location: C:\Scripts\vaultwarden-cloud-backup.ps1
# 
# Backs up Vaultwarden data to Google Drive (encrypted)
# =============================================================================

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$backupDir = "C:\Backups\vaultwarden"
$encryptionPassword = $env:VAULTWARDEN_BACKUP_PASSWORD
if (-not $encryptionPassword) {
    Write-Host "ERROR: VAULTWARDEN_BACKUP_PASSWORD environment variable is not set" -ForegroundColor Red
    exit 1
}

# Create backup directory
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Host "===== Vaultwarden Cloud Backup =====" -ForegroundColor Cyan
Write-Host "Started: $(Get-Date)" -ForegroundColor Gray

# Step 1: Export Vaultwarden data from Docker volume
Write-Host "`n[1/4] Exporting Vaultwarden data..." -ForegroundColor Yellow
$tempBackup = "$backupDir\vaultwarden-$timestamp"
New-Item -ItemType Directory -Force -Path $tempBackup | Out-Null

docker run --rm `
    -v vaultwarden_vaultwarden-data:/data:ro `
    -v ${tempBackup}:/backup `
    alpine sh -c "cp -r /data/* /backup/"

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to export Vaultwarden data" -ForegroundColor Red
    exit 1
}
Write-Host "  Exported to: $tempBackup" -ForegroundColor Green

# Step 2: Create encrypted zip
Write-Host "`n[2/4] Creating encrypted archive..." -ForegroundColor Yellow
$zipFile = "$backupDir\vaultwarden-$timestamp.zip"

# Use 7-Zip for encryption (install if needed: winget install 7zip.7zip)
& "C:\Program Files\7-Zip\7z.exe" a -tzip -p"$encryptionPassword" -mem=AES256 $zipFile "$tempBackup\*" | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create encrypted archive" -ForegroundColor Red
    exit 1
}
Write-Host "  Created: $zipFile" -ForegroundColor Green

# Step 3: Upload to Google Drive
Write-Host "`n[3/4] Uploading to Google Drive..." -ForegroundColor Yellow
rclone copy $zipFile gdrive:/Backups/Vaultwarden/ --progress

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to upload to Google Drive" -ForegroundColor Red
    exit 1
}
Write-Host "  Uploaded successfully!" -ForegroundColor Green

# Step 4: Cleanup
Write-Host "`n[4/4] Cleaning up..." -ForegroundColor Yellow
Remove-Item -Recurse -Force $tempBackup
Write-Host "  Temporary files removed" -ForegroundColor Green

# Keep only last 5 local backups
$oldBackups = Get-ChildItem "$backupDir\*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -Skip 5
foreach ($old in $oldBackups) {
    Remove-Item $old.FullName -Force
    Write-Host "  Removed old backup: $($old.Name)" -ForegroundColor Gray
}

# Cleanup old Google Drive backups (keep last 10)
Write-Host "`n[5/5] Cleaning old cloud backups..." -ForegroundColor Yellow
$cloudFiles = rclone lsf gdrive:/Backups/Vaultwarden/ --files-only | Sort-Object -Descending | Select-Object -Skip 10
foreach ($file in $cloudFiles) {
    if ($file) {
        rclone delete "gdrive:/Backups/Vaultwarden/$file"
        Write-Host "  Removed old cloud backup: $file" -ForegroundColor Gray
    }
}

Write-Host "`n===== Backup Complete! =====" -ForegroundColor Cyan
Write-Host "Local: $zipFile" -ForegroundColor White
Write-Host "Cloud: gdrive:/Backups/Vaultwarden/vaultwarden-$timestamp.zip" -ForegroundColor White
Write-Host "Finished: $(Get-Date)" -ForegroundColor Gray