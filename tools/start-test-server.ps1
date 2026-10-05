# Society Gate - one-click TEST server for Windows.
# Started by START-TEST-SERVER.bat. Downloads PocketBase (first time only),
# finds this laptop's Wi-Fi address, creates test logins and starts the server.

$ErrorActionPreference = 'Stop'
$PbVersion = '0.40.3'
$Root  = Split-Path -Parent $PSScriptRoot
$PbDir = Join-Path $Root 'backend\pocketbase'
$PbExe = Join-Path $PbDir 'pocketbase.exe'

function Say($text, $color = 'White') { Write-Host $text -ForegroundColor $color }

Say ''
Say '=============================================' Cyan
Say '   SOCIETY GATE - TEST SERVER' Cyan
Say '=============================================' Cyan
Say ''

# 1. Download PocketBase the first time
if (-not (Test-Path $PbExe)) {
    Say 'First time: downloading the server program (about 15 MB)...' Yellow
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $url  = "https://github.com/pocketbase/pocketbase/releases/download/v$PbVersion/pocketbase_${PbVersion}_windows_$arch.zip"
    $zip  = Join-Path $env:TEMP 'pocketbase-download.zip'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $PbDir -Force
        Remove-Item $zip -ErrorAction SilentlyContinue
    } catch {
        Say ''
        Say 'Could not download the server program. Check the internet and try again.' Red
        Say "Details: $($_.Exception.Message)" Red
        exit 1
    }
    Say 'Downloaded.' Green
}

# 2. Find this laptop's Wi-Fi / LAN address
$ip = $null
try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object {
            $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
            $_.InterfaceAlias -notmatch 'vEthernet|VirtualBox|VMware|Loopback|Bluetooth|WSL|Hyper-V'
        } |
        Sort-Object { if ($_.InterfaceAlias -match 'Wi-?Fi|Wireless|WLAN') { 0 } else { 1 } } |
        Select-Object -First 1).IPAddress
} catch {}
if (-not $ip) {
    try {
        $ip = [string]([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notmatch '^(127\.|169\.254\.)' } |
            Select-Object -First 1)
    } catch {}
}
if (-not $ip) { $ip = 'YOUR-LAPTOP-IP' }
$server = "http://${ip}:8090"

# 3. Settings for the test
$env:TEST_MODE       = '1'
$env:NTFY_URL        = 'https://ntfy.sh'
$env:NTFY_PUBLIC_URL = 'https://ntfy.sh'
$env:PUBLIC_URL      = $server
$env:EXPIRE_MINUTES  = '2'

# 4. Show what to type on the phone
Say ''
Say '---------------------------------------------' Green
Say ' ON YOUR PHONE, TYPE THIS SERVER ADDRESS:' Green
Say ''
Say "     $server" Yellow
Say ''
Say ' Test logins (password for all: Test12345)' Green
Say '     Resident of house 245 : res245@test.com'
Say '     Guard                 : guard@test.com'
Say ''
Say ' Admin website on this laptop:' Green
Say '     http://localhost:8090/_/   (admin@test.com)'
Say '---------------------------------------------' Green
Say ''
Say 'If Windows asks about the firewall: tick "Private networks" and click "Allow access".' Yellow
Say 'KEEP THIS WINDOW OPEN while testing. Closing it stops the server.' Yellow
Say ''

# 5. Start the server (runs until the window is closed)
Set-Location $PbDir
& $PbExe serve --http "0.0.0.0:8090"
