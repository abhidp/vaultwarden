# =============================================================================
# Vaultwarden → Bitwarden Cloud Sync Script
# Location: C:\vaultwarden\sync-to-bitwarden-cloud.ps1
#
# Exports vault from self-hosted Vaultwarden and imports into Bitwarden cloud
# (free tier) as a cold backup. Purges cloud vault before import to avoid
# duplicates.
#
# NOTE: The export file temporarily contains unencrypted passwords on disk.
#       It is deleted immediately after import.
#
# Required environment variables:
#   VW_API_CLIENTID       - Vaultwarden API client ID  (from Vaultwarden web vault → Settings → Security → Keys → API Key)
#   VW_API_CLIENTSECRET   - Vaultwarden API client secret
#   VW_MASTER_PASSWORD    - Vaultwarden master password
#   BW_CLOUD_CLIENTID     - Bitwarden cloud API client ID  (from vault.bitwarden.com → Settings → Security → Keys → API Key)
#   BW_CLOUD_CLIENTSECRET - Bitwarden cloud API client secret
#   BW_CLOUD_PASSWORD     - Bitwarden cloud master password
#
# Install Bitwarden CLI:
#   winget install Bitwarden.CLI
# =============================================================================

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$tempDir = "$env:TEMP\vw-sync-$timestamp"
$exportFile = "$tempDir\vault-export.json"
$logFile = "C:\vaultwarden\sync-log.txt"

# Vaultwarden server URL (your self-hosted instance)
$vaultwardenUrl = "https://nucboxg3-plus.tail781be8.ts.net:8443"

# =============================================================================
# Helper function: log to console and file
# =============================================================================
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $logFile -Value $logEntry
}

# =============================================================================
# Preflight checks
# =============================================================================
Write-Log "===== Vaultwarden → Bitwarden Cloud Sync =====" "Cyan"
Write-Log "Started: $(Get-Date)"

# Check bw CLI is installed
if (-not (Get-Command "bw" -ErrorAction SilentlyContinue)) {
    Write-Log "ERROR: Bitwarden CLI (bw) not found. Install with: winget install Bitwarden.CLI" "Red"
    exit 1
}

# Check required environment variables
$requiredVars = @(
    "VW_API_CLIENTID", "VW_API_CLIENTSECRET", "VW_MASTER_PASSWORD",
    "BW_CLOUD_CLIENTID", "BW_CLOUD_CLIENTSECRET", "BW_CLOUD_PASSWORD"
)
foreach ($var in $requiredVars) {
    if (-not [Environment]::GetEnvironmentVariable($var)) {
        Write-Log "ERROR: Environment variable $var is not set" "Red"
        exit 1
    }
}

# Create temp directory
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# =============================================================================
# STEP 1: Export from Vaultwarden
# =============================================================================
Write-Log "`n[1/5] Connecting to Vaultwarden..." "Yellow"

# Force logout and ignore any errors (may not be logged in)
$ErrorActionPreference = "Continue"
bw logout 2>&1 | Out-Null
$ErrorActionPreference = "Stop"

bw config server $vaultwardenUrl 2>&1 | Out-Null

$env:BW_CLIENTID = $env:VW_API_CLIENTID
$env:BW_CLIENTSECRET = $env:VW_API_CLIENTSECRET

Write-Log "  Logging in to Vaultwarden..." "Gray"
$loginOutput = bw login --apikey --raw 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: Failed to login to Vaultwarden" "Red"
    Write-Log "  Detail: $loginOutput" "Red"
    exit 1
}

Write-Log "  Unlocking vault..." "Gray"
$env:BW_PASSWORD = $env:VW_MASTER_PASSWORD
$vwSession = (bw unlock --passwordenv BW_PASSWORD --raw)
if ($LASTEXITCODE -ne 0 -or -not $vwSession) {
    Write-Log "ERROR: Failed to unlock Vaultwarden vault" "Red"
    bw logout 2>$null
    exit 1
}

Write-Log "  Syncing vault..." "Gray"
bw sync --session $vwSession --quiet

Write-Log "[2/5] Exporting vault..." "Yellow"
bw export --session $vwSession --format json --output $exportFile
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exportFile)) {
    Write-Log "ERROR: Failed to export vault" "Red"
    bw logout 2>$null
    exit 1
}

$exportSize = (Get-Item $exportFile).Length
Write-Log "  Exported vault ($exportSize bytes)" "Green"

# Count items for verification later
$exportData = Get-Content $exportFile | ConvertFrom-Json
$exportItemCount = $exportData.items.Count
$exportFolderCount = $exportData.folders.Count
Write-Log "  Items: $exportItemCount | Folders: $exportFolderCount" "Green"

if ($exportItemCount -eq 0) {
    Write-Log "ERROR: Export contains 0 items. Aborting to prevent accidental purge." "Red"
    bw logout 2>$null
    Remove-Item -Recurse -Force $tempDir
    exit 1
}

$ErrorActionPreference = "Continue"
bw logout 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
Write-Log "  Logged out of Vaultwarden" "Gray"

# =============================================================================
# STEP 2: Login to Bitwarden Cloud
# =============================================================================
Write-Log "`n[3/5] Connecting to Bitwarden cloud..." "Yellow"

bw config server https://vault.bitwarden.com 2>&1 | Out-Null

$env:BW_CLIENTID = $env:BW_CLOUD_CLIENTID
$env:BW_CLIENTSECRET = $env:BW_CLOUD_CLIENTSECRET

Write-Log "  Logging in to Bitwarden cloud..." "Gray"
$loginOutput = bw login --apikey --raw 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: Failed to login to Bitwarden cloud" "Red"
    Write-Log "  Detail: $loginOutput" "Red"
    Remove-Item -Recurse -Force $tempDir
    exit 1
}

$env:BW_PASSWORD = $env:BW_CLOUD_PASSWORD
$cloudSession = (bw unlock --passwordenv BW_PASSWORD --raw)
if ($LASTEXITCODE -ne 0 -or -not $cloudSession) {
    Write-Log "ERROR: Failed to unlock Bitwarden cloud vault" "Red"
    bw logout 2>$null
    Remove-Item -Recurse -Force $tempDir
    exit 1
}

# =============================================================================
# STEP 3: Purge Bitwarden Cloud vault via API (single request, instant)
# =============================================================================
Write-Log "`n[4/5] Purging Bitwarden cloud vault..." "Yellow"

# Bitwarden API requires version headers on all requests
$bwVersion = (bw --version).Trim()
$versionHeaders = @{
    "Bitwarden-Client-Name"    = "cli"
    "Bitwarden-Client-Version" = $bwVersion
}

# Get access token from Bitwarden identity endpoint
Write-Log "  Getting API access token..." "Gray"
$tokenBody = "grant_type=client_credentials&client_id=$($env:BW_CLOUD_CLIENTID)&client_secret=$($env:BW_CLOUD_CLIENTSECRET)&scope=api&deviceType=6&deviceName=vault-sync-script&deviceIdentifier=sync-script-$(hostname)"

$tokenResponse = Invoke-RestMethod -Uri "https://identity.bitwarden.com/connect/token" `
    -Method Post -ContentType "application/x-www-form-urlencoded" `
    -Body $tokenBody -Headers $versionHeaders
$accessToken = $tokenResponse.access_token

if (-not $accessToken) {
    Write-Log "ERROR: Failed to get API access token" "Red"
    Remove-Item -Recurse -Force $tempDir
    exit 1
}
Write-Log "  Got API access token" "Gray"

# Get KDF parameters from prelogin endpoint
Write-Log "  Getting KDF parameters..." "Gray"
$preloginHeaders = $versionHeaders.Clone()
$preloginHeaders["Content-Type"] = "application/json"

# Get email from profile
$profileHeaders = $versionHeaders.Clone()
$profileHeaders["Authorization"] = "Bearer $accessToken"
$profile = Invoke-RestMethod -Uri "https://vault.bitwarden.com/api/accounts/profile" `
    -Method Get -Headers $profileHeaders
$cloudEmail = $profile.email

$preloginBody = @{ email = $cloudEmail } | ConvertTo-Json
$prelogin = Invoke-RestMethod -Uri "https://identity.bitwarden.com/accounts/prelogin" `
    -Method Post -Headers $preloginHeaders -Body $preloginBody
$kdfIterations = $prelogin.kdfIterations
Write-Log "  KDF iterations: $kdfIterations" "Gray"

# Compute master password hash: PBKDF2-SHA256
# Step 1: masterKey = PBKDF2(password, email, kdfIterations, 32 bytes)
# Step 2: masterPasswordHash = Base64(PBKDF2(masterKey, password, 1, 32 bytes))
$emailBytes = [System.Text.Encoding]::UTF8.GetBytes($cloudEmail.ToLower())
$pwBytes = [System.Text.Encoding]::UTF8.GetBytes($env:BW_CLOUD_PASSWORD)

$pbkdf2_1 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($pwBytes, $emailBytes, $kdfIterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$masterKey = $pbkdf2_1.GetBytes(32)

$pbkdf2_2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($masterKey, $pwBytes, 1, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
$masterPasswordHash = [Convert]::ToBase64String($pbkdf2_2.GetBytes(32))

# Purge vault via API — single request, deletes all ciphers instantly
Write-Log "  Purging vault via API..." "Gray"
$purgeHeaders = $versionHeaders.Clone()
$purgeHeaders["Authorization"] = "Bearer $accessToken"
$purgeHeaders["Content-Type"] = "application/json"
$purgeBody = @{ masterPasswordHash = $masterPasswordHash } | ConvertTo-Json

Invoke-WebRequest -Uri "https://vault.bitwarden.com/api/ciphers/purge" `
    -Method Post -Headers $purgeHeaders -Body $purgeBody -UseBasicParsing | Out-Null
Write-Log "  Vault purged via API (all items deleted)" "Green"

# Delete all folders (API purge only removes ciphers, not folders)
$cloudFolders = bw list folders --session $cloudSession | ConvertFrom-Json
$folderCount = 0
foreach ($folder in $cloudFolders) {
    if ($folder.id) {
        bw delete folder $folder.id --session $cloudSession --quiet 2>$null
        $folderCount++
    }
}
if ($folderCount -gt 0) { Write-Log "  Deleted $folderCount folders" "Gray" }
Write-Log "  Purge complete" "Green"

# =============================================================================
# STEP 4: Import vault into Bitwarden Cloud
# =============================================================================
Write-Log "`n[5/5] Importing vault to Bitwarden cloud..." "Yellow"

bw import bitwardenjson $exportFile --session $cloudSession --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: Failed to import vault to Bitwarden cloud" "Red"
    Write-Log "CRITICAL: Cloud vault has been purged but import failed!" "Red"
    Write-Log "The export file is preserved at: $exportFile" "Red"
    Write-Log "Manually import via: bw import bitwardenjson $exportFile" "Red"
    bw logout 2>$null
    exit 1
}

# Verify import
bw sync --session $cloudSession --quiet
$verifyItems = bw list items --session $cloudSession | ConvertFrom-Json
$verifyCount = $verifyItems.Count
Write-Log "  Imported and verified: $verifyCount items (expected: $exportItemCount)" "Green"

if ($verifyCount -ne $exportItemCount) {
    Write-Log "WARNING: Item count mismatch. Expected $exportItemCount, got $verifyCount" "Yellow"
}

$ErrorActionPreference = "Continue"
bw logout 2>&1 | Out-Null
$ErrorActionPreference = "Stop"
Write-Log "  Logged out of Bitwarden cloud" "Gray"

# =============================================================================
# STEP 5: Cleanup
# =============================================================================
Write-Log "`nCleaning up temporary files..." "Yellow"
Remove-Item -Recurse -Force $tempDir
Write-Log "  Export file securely deleted" "Green"

# Clear sensitive env vars from this session
$env:BW_CLIENTID = $null
$env:BW_CLIENTSECRET = $null
$env:BW_PASSWORD = $null

Write-Log "`n===== Sync Complete! =====" "Cyan"
Write-Log "Source: Vaultwarden ($vaultwardenUrl)"
Write-Log "Destination: Bitwarden Cloud (vault.bitwarden.com)"
Write-Log "Items synced: $exportItemCount"
Write-Log "Finished: $(Get-Date)"
