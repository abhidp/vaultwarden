# Wrapper script for Task Scheduler
# Loads user environment variables and runs the sync script

# Load env vars (Task Scheduler runs as SYSTEM or user but doesn't load User env vars automatically)
"VW_API_CLIENTID","VW_API_CLIENTSECRET","VW_MASTER_PASSWORD","BW_CLOUD_CLIENTID","BW_CLOUD_CLIENTSECRET","BW_CLOUD_PASSWORD" | ForEach-Object {
    Set-Item "env:$_" ([Environment]::GetEnvironmentVariable($_, "User"))
}

# Ensure bw CLI is in PATH
$bwPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Bitwarden.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe"
if (Test-Path $bwPath) {
    $env:PATH = "$env:PATH;$bwPath"
}

# Run the sync script
& "C:\vaultwarden\sync-to-bitwarden-cloud.ps1"
