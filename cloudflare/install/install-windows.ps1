# Windows PowerShell 5.1+; installs only for the current user.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$cpu = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($cpu.ToUpperInvariant()) { 'AMD64' { 'amd64' }; 'ARM64' { 'arm64' }; default { throw 'Only x64 and ARM64 Windows are supported.' } }
$version = 'v0.1.0'
$base = "https://github.com/xrefft/xrefft.github.io/releases/download/cf-speed-$version"
$asset = "cf-speed-windows-$arch.zip"
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$installDir = Join-Path $env:LOCALAPPDATA 'CloudflareIPTest'
if (Test-Path $installDir) { throw "Install directory exists. Exit cf-speed and move the old directory before installing: $installDir" }
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    Invoke-WebRequest -UseBasicParsing "$base/$asset" -OutFile (Join-Path $tempDir $asset)
    Invoke-WebRequest -UseBasicParsing "$base/SHA256SUMS" -OutFile (Join-Path $tempDir 'SHA256SUMS')
    $checksumLines = @(Get-Content (Join-Path $tempDir 'SHA256SUMS') | Where-Object { $_ -match ('^[0-9a-f]{64}\s+' + [regex]::Escape($asset) + '$') })
    if ($checksumLines.Count -ne 1) { throw 'Checksum entry missing or duplicated.' }
    $expected = ($checksumLines[0] -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $tempDir $asset)).Hash
    if ($actual -ne $expected) { throw 'SHA-256 verification failed; installation stopped.' }
    Expand-Archive (Join-Path $tempDir $asset) -DestinationPath (Join-Path $tempDir 'unpacked')
    New-Item -ItemType Directory -Path $installDir | Out-Null
    $exe = Join-Path $installDir 'cf-speed.exe'
    Copy-Item (Join-Path $tempDir 'unpacked/cf-speed.exe') $exe
    $protocol = 'HKCU:\Software\Classes\cfspeed'
    New-Item -Path "$protocol\shell\open\command" -Force | Out-Null
    Set-Item $protocol -Value 'URL:Cloudflare IP Test'
    New-ItemProperty $protocol -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    Set-Item "$protocol\shell\open\command" -Value ('"' + $exe + '" --open')
    Write-Host "Installed: $exe"
    Write-Host 'Use the website launcher. To uninstall, exit cf-speed, remove this directory and HKCU\Software\Classes\cfspeed.'
    Start-Process -FilePath $exe -ArgumentList '--open'
} finally { Remove-Item $tempDir -Recurse -Force }
