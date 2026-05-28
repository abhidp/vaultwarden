$logFile = "C:\vaultwarden\update-log.txt"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Set-Location C:\vaultwarden

$before = docker inspect --format='{{.Image}}' vaultwarden 2>$null

docker compose pull | Out-Null
docker compose up -d --force-recreate | Out-Null

$after = docker inspect --format='{{.Image}}' vaultwarden 2>$null

if ($before -ne $after) {
    Add-Content $logFile "[$timestamp] Updated vaultwarden: $($before.Substring(0,12)) -> $($after.Substring(0,12))"
} else {
    Add-Content $logFile "[$timestamp] No update available"
}
