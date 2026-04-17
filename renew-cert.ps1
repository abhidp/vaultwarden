  # Vaultwarden Tailscale Certificate Auto-Renewal
  $certFile = "C:\vaultwarden\nucboxg3-plus.tail781be8.ts.net.crt"
  $keyFile = "C:\vaultwarden\nucboxg3-plus.tail781be8.ts.net.key"
  $domain = "nucboxg3-plus.tail781be8.ts.net"

  # Remove old cert files
  Remove-Item $certFile -Force -ErrorAction SilentlyContinue
  Remove-Item $keyFile -Force -ErrorAction SilentlyContinue

  # Generate new cert (use full path)
  & "C:\Program Files\Tailscale\tailscale.exe" cert --cert-file $certFile --key-file $keyFile $domain

  # Restart Vaultwarden (use full path)
  & "C:\Program Files\Docker\Docker\resources\bin\docker.exe" compose -f C:\vaultwarden\compose.yaml restart
