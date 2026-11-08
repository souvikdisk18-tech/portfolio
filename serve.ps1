$root = if ($PSScriptRoot) { $PSScriptRoot } else { "e:\portfolio" }

# Terminate any previous cloudflared or stray instances
try {
    Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
} catch {}

# Initialize HttpListener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:3000/")
$listener.Prefixes.Add("http://127.0.0.1:3000/")
$listener.Prefixes.Add("http://localhost:8080/")
$listener.Prefixes.Add("http://127.0.0.1:8080/")
$listener.Prefixes.Add("http://localhost:5000/")
$listener.Prefixes.Add("http://127.0.0.1:5000/")

try {
    $listener.Start()
} catch {
    Write-Error "Failed to start HttpListener: $_"
    exit 1
}

# Detect Local Network (Wi-Fi / Ethernet) IP
$lanIp = $null
try {
    $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi*','Ethernet*' -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
    if (-not $lanIp) {
        $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
    }
} catch {}

# Start Cloudflare Public Tunnel for Mobile & Remote Devices
$cloudflaredExe = Join-Path $root "cloudflared.exe"
$tunnelUrlFile = Join-Path $root "tunnel_url.txt"
$tunnelLog = Join-Path $root "tunnel.log"
$tunnelUrl = $null
$cfProc = $null

if (Test-Path $cloudflaredExe) {
    if (Test-Path $tunnelUrlFile) { Remove-Item $tunnelUrlFile -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tunnelLog) { Remove-Item $tunnelLog -Force -ErrorAction SilentlyContinue }

    $cfPsi = New-Object System.Diagnostics.ProcessStartInfo
    $cfPsi.FileName = $cloudflaredExe
    $cfPsi.Arguments = "tunnel --url http://127.0.0.1:3000 --logfile `"$tunnelLog`" --no-autoupdate --no-prechecks"
    $cfPsi.UseShellExecute = $false
    $cfPsi.CreateNoWindow = $true

    $cfProc = [System.Diagnostics.Process]::Start($cfPsi)

    # Wait up to 12 seconds for the public trycloudflare.com URL
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 400
        if (Test-Path $tunnelLog) {
            $logContent = Get-Content $tunnelLog -Raw -ErrorAction SilentlyContinue
            if ($logContent -and $logContent -match '(https://[a-zA-Z0-9-]+\.trycloudflare\.com)') {
                $tunnelUrl = $matches[1]
                [System.IO.File]::WriteAllText($tunnelUrlFile, $tunnelUrl)
                break
            }
        }
    }
}

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "   SUMAN GARAI PORTFOLIO - SERVER RUNNING SUCCESSFULLY" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " [1] LAPTOP / LOCAL MACHINE:" -ForegroundColor Yellow
Write-Host "     http://localhost:3000/" -ForegroundColor Yellow
Write-Host "     http://127.0.0.1:3000/" -ForegroundColor Yellow
if ($lanIp) {
    Write-Host ""
    Write-Host " [2] LOCAL WI-FI NETWORK (If devices are on the same Wi-Fi):" -ForegroundColor Magenta
    Write-Host "     http://${lanIp}:3000/" -ForegroundColor Magenta
}
if ($tunnelUrl) {
    Write-Host ""
    Write-Host " [3] UNIVERSAL MOBILE LINK (Works on ANY phone/tablet/laptop, ANYWHERE):" -ForegroundColor Green
    Write-Host "     $tunnelUrl" -ForegroundColor Green
}
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host ""

try {
    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
        } catch {
            if (-not $listener.IsListening) { break }
            continue
        }

        try {
            $request = $context.Request
            $response = $context.Response

            $rawPath = [System.Uri]::UnescapeDataString($request.Url.LocalPath.TrimStart('/'))
            if ([string]::IsNullOrEmpty($rawPath)) {
                $rawPath = "index.html"
            }

            $rawPath = $rawPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $localPath = [System.IO.Path]::Combine($root, $rawPath)

            if ([System.IO.File]::Exists($localPath)) {
                $ext = [System.IO.Path]::GetExtension($localPath).ToLower()
                $contentType = switch ($ext) {
                    ".html" { "text/html; charset=utf-8" }
                    ".css"  { "text/css; charset=utf-8" }
                    ".js"   { "application/javascript; charset=utf-8" }
                    ".jpg"  { "image/jpeg" }
                    ".jpeg" { "image/jpeg" }
                    ".png"  { "image/png" }
                    ".webp" { "image/webp" }
                    ".svg"  { "image/svg+xml" }
                    ".ico"  { "image/x-icon" }
                    ".json" { "application/json; charset=utf-8" }
                    default { "application/octet-stream" }
                }

                $cacheControl = switch ($ext) {
                    ".html" { "no-cache, no-store, must-revalidate" }
                    ".css"  { "no-cache, no-store, must-revalidate" }
                    ".js"   { "no-cache, no-store, must-revalidate" }
                    default { "public, max-age=86400" }
                }

                $response.ContentType = $contentType
                $response.AddHeader("Access-Control-Allow-Origin", "*")
                $response.AddHeader("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
                $response.AddHeader("Access-Control-Allow-Headers", "*")
                $response.AddHeader("Cache-Control", $cacheControl)
                $response.AddHeader("Pragma", "no-cache")
                $response.AddHeader("Expires", "0")

                if ($request.HttpMethod -eq "OPTIONS") {
                    $response.StatusCode = 200
                    $response.Close()
                    continue
                }

                $bytes = [System.IO.File]::ReadAllBytes($localPath)
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.OutputStream.Flush()
                $response.Close()
            } else {
                $response.StatusCode = 404
                $buffer = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.OutputStream.Flush()
                $response.Close()
            }
        } catch {
            try { $context.Response.Close() } catch {}
        }
    }
} finally {
    if ($cfProc -and -not $cfProc.HasExited) {
        try { $cfProc.Kill() } catch {}
    }
    if ($listener -and $listener.IsListening) {
        try { $listener.Stop() } catch {}
    }
}
