# Vaultwarden Self-Hosted Password Manager

A self-hosted Bitwarden-compatible password manager running in Docker, accessible remotely via Tailscale with automated TLS certificate renewal and encrypted backups to Google Drive.

## Overview

This project sets up Vaultwarden (an unofficial Bitwarden-compatible server) with Tailscale-issued TLS certificates for secure HTTPS access across all your devices — including from outside your home network (mobile data, other WiFi networks, etc.).

## Features

- **Vaultwarden Server**: Lightweight Bitwarden-compatible password manager
- **Tailscale Networking**: Secure remote access from anywhere via Tailscale VPN
- **SSL/TLS Encryption**: Tailscale-issued Let's Encrypt certificates (auto-renewed weekly)
- **Automated Backups**: Encrypted backups to Google Drive via PowerShell script
- **Docker Deployment**: Containerized deployment using Docker Compose
- **Data Persistence**: Persistent Docker volume for data storage

## Prerequisites

- Docker and Docker Compose installed
- Tailscale installed and configured on server and client devices
- PowerShell (for backup and cert renewal scripts)
- 7-Zip installed (for encrypted backups)
- rclone configured with Google Drive

## Quick Start

1. **Clone or download this project** to `C:\vaultwarden`

2. **Generate Tailscale TLS certificates**:
   ```powershell
   tailscale cert --cert-file C:\vaultwarden\nucboxg3-plus.tail781be8.ts.net.crt --key-file C:\vaultwarden\nucboxg3-plus.tail781be8.ts.net.key nucboxg3-plus.tail781be8.ts.net
   ```

3. **Start the service**:
   ```powershell
   docker compose up -d
   ```

4. **Set up automatic certificate renewal** (see [Certificate Renewal](#certificate-renewal) below)

5. **Access Vaultwarden**:
   - URL: `https://nucboxg3-plus.tail781be8.ts.net:8443`
   - Accessible from any device on your Tailscale network
   - Signups are disabled by default

## Configuration

### Docker Compose Settings

- **Port**: 8443 (external) → 80 (internal)
- **Domain**: `https://nucboxg3-plus.tail781be8.ts.net:8443`
- **Signups**: Disabled (`SIGNUPS_ALLOWED=false`)
- **TLS**: Enabled with custom certificates

### Environment Variables

- `DOMAIN`: Your Vaultwarden server URL
- `SIGNUPS_ALLOWED`: Control new user registration
- `ROCKET_TLS`: TLS certificate configuration

## Backup System

The `backup.ps1` script provides automated encrypted backups:

### Backup Process

1. **Export Data**: Exports Vaultwarden data from Docker volume
2. **Encrypt Archive**: Creates AES256-encrypted ZIP archive
3. **Cloud Upload**: Uploads encrypted backup to Google Drive
4. **Local Cleanup**: Removes temporary files and old local backups
5. **Cloud Cleanup**: Removes old cloud backups (keeps last 10)

### Running Backups

```powershell
.\backup.ps1
```

### Backup Configuration

- **Local Backup Directory**: `C:\Backups\vaultwarden`
- **Cloud Storage**: Google Drive (`gdrive:/Backups/Vaultwarden/`)
- **Encryption**: AES256 with password (change in script)
- **Retention**: 5 local backups, 10 cloud backups

### Required Tools

- **7-Zip**: For encrypted archive creation
  ```powershell
  winget install 7zip.7zip
  ```
- **rclone**: For Google Drive synchronization
  - Configure with: `rclone config`

## Certificate Renewal

Tailscale TLS certificates are Let's Encrypt certs that **expire every 90 days**. The `renew-cert.ps1` script handles automatic renewal.

### How It Works

1. Removes the old certificate and key files
2. Generates fresh certificates via `tailscale cert`
3. Restarts the Vaultwarden container to pick up the new cert

### Scheduled Task Setup

The renewal runs as a Windows Scheduled Task every Sunday at 3 AM:

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\vaultwarden\renew-cert.ps1" -WorkingDirectory "C:\vaultwarden"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3:00AM
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName "Vaultwarden Cert Renewal" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -User $env:USERNAME
```

### Manual Renewal

```powershell
# Run the renewal script directly
powershell.exe -ExecutionPolicy Bypass -File C:\vaultwarden\renew-cert.ps1

# Or trigger the scheduled task
Start-ScheduledTask -TaskName "Vaultwarden Cert Renewal"
```

### Verify Scheduled Task Status

```powershell
Get-ScheduledTaskInfo -TaskName "Vaultwarden Cert Renewal"
# LastTaskResult should be 0
```

## Security Notes

1. **Change Encryption Password**: Update the default password in `backup.ps1`
2. **Certificate Expiry**: Ensure the cert renewal scheduled task is running (check `LastTaskResult`)
3. **Network Access**: Vaultwarden is only accessible via Tailscale — no ports are exposed to the public internet
4. **Regular Updates**: Keep the Vaultwarden image updated

## Maintenance

### Update Vaultwarden

```powershell
docker compose pull
docker compose up -d --force-recreate
```

### Manual Backup

```powershell
.\backup.ps1
```

### Data Recovery

1. Download encrypted backup from Google Drive
2. Decrypt using 7-Zip with your password
3. Restore data to Docker volume:
   ```powershell
   docker run --rm -v vaultwarden_vaultwarden-data:/data -v C:\path\to\backup:/backup alpine sh -c "cp -r /backup/* /data/"
   ```

## File Structure

```
vaultwarden/
├── README.md                                    # This file
├── compose.yaml                                 # Docker Compose configuration
├── backup.ps1                                   # Encrypted backup to Google Drive
├── renew-cert.ps1                               # Tailscale TLS certificate renewal
├── nucboxg3-plus.tail781be8.ts.net.crt          # TLS certificate (auto-renewed)
└── nucboxg3-plus.tail781be8.ts.net.key          # TLS private key (auto-renewed)
```

## Troubleshooting

### Common Issues

1. **`CertificateUnknown` TLS errors**: Certificate has expired — run `renew-cert.ps1` or trigger the scheduled task
2. **Rocket launches on `http://` instead of `https://`**: Certificate files are missing or volume mounts in `compose.yaml` are incorrect
3. **Port Conflicts**: Ensure port 8443 is not in use
4. **Backup Failures**: Check rclone configuration and Google Drive access

### Logs

```powershell
# Vaultwarden container logs
docker compose logs vaultwarden

# Check cert renewal task status
Get-ScheduledTaskInfo -TaskName "Vaultwarden Cert Renewal"
```

## Support

- **Vaultwarden Documentation**: https://github.com/dani-garcia/vaultwarden
- **Docker Documentation**: https://docs.docker.com/
- **rclone Documentation**: https://rclone.org/

## License

This project configuration is provided as-is. Vaultwarden itself is licensed under AGPL-3.0.
