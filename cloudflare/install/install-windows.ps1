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
$exe = Join-Path $installDir 'cf-speed.exe'
$stdoutLog = Join-Path $installDir 'runtime.stdout.log'
$stderrLog = Join-Path $installDir 'runtime.stderr.log'
$stage = 'Prepare'
# HttpWebRequest supports Windows PowerShell 5.1: a 15-second connect/header
# timeout, 15-second read timeout, and a 120-second budget for each attempt.
function Receive-ReleaseFile([string]$Url, [string]$Destination) {
    for ($downloadAttempt = 1; $downloadAttempt -le 3; $downloadAttempt++) {
        $response = $null; $inputStream = $null; $outputStream = $null; $request = $null
        $watch = [Diagnostics.Stopwatch]::StartNew()
        try {
            $request = [Net.HttpWebRequest]::Create($Url)
            $request.Timeout = 15000
            $request.ReadWriteTimeout = 15000
            $request.UserAgent = 'CloudflareIPTest-Installer/0.1.0'
            $response = $request.GetResponse()
            if ($response.ResponseUri.Scheme -ne 'https') { throw 'Refusing non-HTTPS download redirect.' }
            $inputStream = $response.GetResponseStream()
            $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write)
            $buffer = New-Object byte[] 65536
            while ($true) {
                $remainingMs = 120000 - [int]$watch.ElapsedMilliseconds
                if ($remainingMs -le 0) { throw 'Download exceeded the 120-second time limit.' }
                $inputStream.ReadTimeout = [Math]::Min(15000, $remainingMs)
                $count = $inputStream.Read($buffer, 0, $buffer.Length)
                if ($count -eq 0) { break }
                $outputStream.Write($buffer, 0, $count)
            }
            return
        } catch {
            Write-Warning "Download attempt $downloadAttempt/3 failed: $($_.Exception.Message)"
            if ($downloadAttempt -eq 3) { throw "Could not download $Url after 3 attempts. $($_.Exception.Message)" }
        } finally {
            if ($outputStream) { $outputStream.Dispose() }
            if ($inputStream) { $inputStream.Dispose() }
            if ($response) { $response.Dispose() }
            if ($request) { $request.Abort() }
            $watch.Stop()
        }
        Start-Sleep -Seconds 2
    }
}
function Test-LocalProbe {
    try {
        # Explicitly bypass configured HTTP proxies for loopback readiness checks.
        $probeRequest = [Net.HttpWebRequest]::Create('http://127.0.0.1:38479/api/info')
        $probeRequest.Proxy = $null
        $probeRequest.Timeout = 2000
        $probeRequest.ReadWriteTimeout = 2000
        $probeResponse = $probeRequest.GetResponse()
        try {
            $reader = New-Object IO.StreamReader($probeResponse.GetResponseStream())
            try {
                $responseText = $reader.ReadToEnd()
                $identity = $responseText | ConvertFrom-Json
                return $identity.app -eq 'cf-speed' -and $identity.version -eq $version
            } finally { $reader.Dispose() }
        } finally { $probeResponse.Dispose() }
    } catch { return $false }
}
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $stage = '1/5 Download'; Write-Host "[$stage] $asset"
    Receive-ReleaseFile "$base/$asset" (Join-Path $tempDir $asset)
    Receive-ReleaseFile "$base/SHA256SUMS" (Join-Path $tempDir 'SHA256SUMS')
    $stage = '2/5 Verify'; Write-Host "[$stage] SHA-256"
    $checksumLines = @(Get-Content (Join-Path $tempDir 'SHA256SUMS') | Where-Object { $_ -match ('^[0-9a-f]{64}\s+' + [regex]::Escape($asset) + '$') })
    if ($checksumLines.Count -ne 1) { throw 'Checksum entry missing or duplicated.' }
    $expected = ($checksumLines[0] -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $tempDir $asset)).Hash
    if ($actual -ne $expected) { throw 'SHA-256 verification failed; installation stopped.' }
    Expand-Archive (Join-Path $tempDir $asset) -DestinationPath (Join-Path $tempDir 'unpacked')
    $packageExe = Join-Path $tempDir 'unpacked/cf-speed.exe'
    if (-not (Test-Path -LiteralPath $packageExe -PathType Leaf)) { throw 'Release package has no cf-speed.exe.' }
    $stage = '3/5 Install'; Write-Host "[$stage] $installDir"
    $copyBinary = $true
    if (Test-Path -LiteralPath $installDir) {
        $directoryItem = Get-Item -LiteralPath $installDir -Force
        if (-not $directoryItem.PSIsContainer -or ($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Install path is not an ordinary directory; it was preserved.' }
        if (Test-Path -LiteralPath $exe) {
            $binaryItem = Get-Item -LiteralPath $exe -Force
            if ($binaryItem.PSIsContainer -or ($binaryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Existing executable is not an ordinary file; it was preserved.' }
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $packageExe).Hash) { throw 'Existing executable differs from this release. Nothing was overwritten. Exit the old program and move its directory manually before installing.' }
            $copyBinary = $false
            Write-Host 'Identical release found. Keeping the binary and repairing startup registration.'
        } elseif (@(Get-ChildItem -LiteralPath $installDir -Force).Count -gt 0) {
            throw 'Existing directory is nonempty and cannot be identified as this tool. It was preserved.'
        }
    } else { New-Item -ItemType Directory -Path $installDir | Out-Null }
    if ($copyBinary) { Copy-Item -LiteralPath $packageExe -Destination $exe }
    $stage = '4/5 Register'; Write-Host "[$stage] Current-user URL handler"
    $protocol = 'HKCU:\Software\Classes\cfspeed'
    $handlerCommand = '"' + $exe + '" --open'
    if (Test-Path "$protocol\shell\open\command") {
        $existingCommand = (Get-Item "$protocol\shell\open\command").GetValue('')
        $registrationName = (Get-Item $protocol).GetValue('')
        if ($existingCommand -ne $handlerCommand -and -not ([string]::IsNullOrEmpty($existingCommand) -and $registrationName -eq 'URL:Cloudflare IP Test')) { throw 'The cfspeed URL handler belongs to a different command. It was preserved; launch the installed executable manually.' }
    } elseif ((Test-Path $protocol) -and (Get-Item $protocol).GetValue('') -ne 'URL:Cloudflare IP Test') { throw 'An unrecognized cfspeed URL registration exists. It was preserved; launch the executable manually.' }
    New-Item -Path "$protocol\shell\open\command" -Force | Out-Null
    Set-Item $protocol -Value 'URL:Cloudflare IP Test'
    New-ItemProperty $protocol -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    Set-Item "$protocol\shell\open\command" -Value $handlerCommand
    $stage = '5/5 Start'; Write-Host "[$stage] Checking local service"
    foreach ($logPath in @($stdoutLog, $stderrLog)) {
        if ((Test-Path -LiteralPath $logPath) -and ((Get-Item -LiteralPath $logPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Log path is a reparse point; preserved: $logPath" }
    }
    # Avoid truncating logs held by an already-running instance during repair.
    if (Test-LocalProbe) {
        try { Start-Process -FilePath $exe -ArgumentList '--open' -ErrorAction Stop | Out-Null } catch { throw "Existing service is ready, but opening its page failed: $($_.Exception.Message)" }
    } else {
        try { Start-Process -FilePath $exe -ArgumentList '--open' -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -ErrorAction Stop | Out-Null } catch { throw "Could not start cf-speed.exe: $($_.Exception.Message)" }
    }
    $ready = $false
    for ($pollAttempt = 0; $pollAttempt -lt 15; $pollAttempt++) {
        if (Test-LocalProbe) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Files are installed, but the expected service did not become ready. Check the logs and port 38479; no existing process was terminated.' }
    Write-Host "Ready: $version http://127.0.0.1:38479/"
    Write-Host 'You can now use the website launcher.'
    Write-Host "Logs: $stdoutLog ; $stderrLog"
} catch {
    Write-Host "[$stage] Installation did not complete: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Logs (if startup was attempted): $stdoutLog ; $stderrLog"
    Write-Host ('Manual start: & "' + $exe + '" --open')
    throw
} finally { Remove-Item -LiteralPath $tempDir -Recurse -Force }
