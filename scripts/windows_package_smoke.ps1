Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $ScriptDir ".."))
$ExampleName = "47_dev_extension_js"
$ProductName = "Proton Dev Extension JS"
$ExecutableName = "proton-dev-extension-js"
$ExampleDir = Join-Path $RepoRoot (Join-Path "examples" $ExampleName)
$DistDir = Join-Path $ExampleDir "target\proton-dist"
$PortableDir = Join-Path $DistDir $ExecutableName
$ArchivePath = Join-Path $DistDir ($ExecutableName + ".zip")
$CdpTimeoutSeconds = 45
$ExitTimeoutSeconds = 20
$HelperTimeoutSeconds = 20

$TempRoot = $null
$Certificate = $null
$CertificateThumbprint = $null
$PfxPath = $null
$AppProcess = $null
$HelperProcessIds = @()
$StdoutLog = $null
$StderrLog = $null
$CleanupErrors = @()
$CertUtil = $null
$OldCertificate = $env:PROTON_WINDOWS_CERTIFICATE
$OldPassword = $env:PROTON_WINDOWS_CERTIFICATE_PASSWORD
$OldTimestamp = $env:PROTON_WINDOWS_TIMESTAMP_URL
$OldDebugPort = $env:PROTON_REMOTE_DEBUGGING_PORT

function Fail {
    param([string]$Message)
    throw $Message
}

function Require-Command {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        Fail "Required command is unavailable: $Name"
    }
    return $command.Source
}

function Require-Path {
    param(
        [string]$Path,
        [string]$Message
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        Fail "$Message Missing: $Path"
    }
}

function Invoke-External {
    param(
        [string]$Command,
        [string[]]$Arguments
    )
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail "Command failed with exit code ${LASTEXITCODE}: $Command"
    }
}

function Invoke-CertUtilWithTimeout {
    param(
        [string]$Arguments,
        [string]$Operation,
        [int]$TimeoutSeconds = 15
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $CertUtil
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            Fail "Unable to start certutil for $Operation"
        }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            Fail "$Operation timed out after $TimeoutSeconds seconds; Windows is likely waiting for interactive certificate trust confirmation"
        }
        $output = ($stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()).Trim()
        if ($process.ExitCode -ne 0) {
            if ($output) {
                Fail "$Operation failed with exit code $($process.ExitCode): $output"
            }
            Fail "$Operation failed with exit code $($process.ExitCode)"
        }
    }
    finally {
        $process.Dispose()
    }
}

function Remove-CertificateFromCurrentUserRoot {
    param([string]$Thumbprint)
    $store = [Security.Cryptography.X509Certificates.X509Store]::new(
        [Security.Cryptography.X509Certificates.StoreName]::Root,
        [Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
    )
    try {
        $store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
        $matches = $store.Certificates.Find(
            [Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
            $Thumbprint,
            $false
        )
        foreach ($match in $matches) {
            $store.Remove($match)
            $match.Dispose()
        }
    }
    finally {
        $store.Close()
        $store.Dispose()
    }
}

function Get-FreeTcpPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()
    return $port
}

function Wait-ForCdpPage {
    param(
        [int]$Port,
        [Diagnostics.Process]$Process
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($CdpTimeoutSeconds)
    $lastError = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Process.HasExited) {
            Fail "Packaged app exited before CDP became ready. Exit code: $($Process.ExitCode)"
        }
        try {
            $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 2
            $page = @($targets) | Where-Object { $_.type -eq "page" } | Select-Object -First 1
            if ($page) {
                return $page
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 200
    }
    if ($lastError) {
        Fail "Timed out waiting for packaged app CDP: $lastError"
    }
    Fail "Timed out waiting for packaged app CDP"
}

function Wait-ForHelpers {
    param(
        [int]$ParentProcessId,
        [string]$ExpectedPath
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($CdpTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $helpers = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentProcessId" | Where-Object { $_.Name -ieq "cef_process.exe" })
        if ($helpers.Count -gt 0) {
            foreach ($helper in $helpers) {
                if (-not $helper.ExecutablePath) {
                    Fail "Unable to inspect cef_process.exe path for PID $($helper.ProcessId)"
                }
                $actualPath = [IO.Path]::GetFullPath($helper.ExecutablePath)
                if (-not $actualPath.Equals($ExpectedPath, [StringComparison]::OrdinalIgnoreCase)) {
                    Fail "CEF helper is running from an unexpected path: $actualPath"
                }
            }
            return $helpers
        }
        Start-Sleep -Milliseconds 200
    }
    Fail "Timed out waiting for cef_process.exe helpers"
}

function Send-CdpBrowserClose {
    param([int]$Port)
    $version = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 3
    $socketUrl = $version.webSocketDebuggerUrl
    if (-not $socketUrl) {
        Fail "CDP did not expose webSocketDebuggerUrl"
    }
    $socket = [Net.WebSockets.ClientWebSocket]::new()
    $timeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(5))
    try {
        $null = $socket.ConnectAsync([Uri]$socketUrl, $timeout.Token).GetAwaiter().GetResult()
        $payload = [Text.Encoding]::UTF8.GetBytes('{"id":1,"method":"Browser.close"}')
        $segment = [ArraySegment[byte]]::new($payload)
        $null = $socket.SendAsync(
            $segment,
            [Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            $timeout.Token
        ).GetAwaiter().GetResult()
    }
    finally {
        $socket.Dispose()
        $timeout.Dispose()
    }
}

function Wait-ForProcessExit {
    param(
        [Diagnostics.Process]$Process,
        [int]$TimeoutSeconds
    )
    if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
        Fail "Process $($Process.Id) did not exit within $TimeoutSeconds seconds"
    }
}

function Wait-ForHelperCleanup {
    param(
        [int[]]$ProcessIds,
        [int]$TimeoutSeconds
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $remaining = @($ProcessIds | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($remaining.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 200
    }
    $remaining = @($ProcessIds | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    Fail "CEF helpers did not exit with the packaged app: $($remaining -join ', ')"
}

try {
    if ($env:OS -ne "Windows_NT") {
        Fail "Windows package smoke requires a Windows host"
    }

    $Moon = Require-Command "moon"
    $Npm = Require-Command "npm.cmd"
    $SignTool = Require-Command "signtool.exe"
    $CertUtil = Require-Command "certutil.exe"
    Require-Path (Join-Path $RepoRoot ".proton\runtime.json") "Run 'moon -C cli run . -- -C .. cef setup' first."
    Require-Path (Join-Path $ExampleDir "moon.proton") "Package smoke example is missing."

    $nodeModules = Join-Path $ExampleDir "frontend\node_modules"
    if (-not (Test-Path -LiteralPath $nodeModules)) {
        Invoke-External $Npm @("--prefix", (Join-Path $ExampleDir "frontend"), "ci")
    }

    $TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("Proton Windows Package Smoke " + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    $PfxPath = Join-Path $TempRoot "temporary-code-signing.pfx"
    $cerPath = Join-Path $TempRoot "temporary-code-signing.cer"
    $passwordText = [Guid]::NewGuid().ToString("N") + [Guid]::NewGuid().ToString("N")
    $securePassword = ConvertTo-SecureString -String $passwordText -AsPlainText -Force
    $subject = "CN=Proton Windows Package Smoke " + [Guid]::NewGuid().ToString("N")

    try {
        $Certificate = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject $subject `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -KeyExportPolicy Exportable `
            -KeyAlgorithm RSA `
            -KeyLength 2048 `
            -HashAlgorithm SHA256 `
            -NotAfter ([DateTime]::Now.AddDays(1))
        $CertificateThumbprint = $Certificate.Thumbprint
        Export-PfxCertificate -Cert $Certificate -FilePath $PfxPath -Password $securePassword | Out-Null
        Export-Certificate -Cert $Certificate -FilePath $cerPath | Out-Null
        $quotedCerPath = '"' + $cerPath + '"'
        Invoke-CertUtilWithTimeout `
            -Arguments "-user -addstore -f Root $quotedCerPath" `
            -Operation "Temporary CurrentUser Root certificate installation"
    }
    catch {
        Fail "Temporary code-signing certificate setup was blocked by system policy: $($_.Exception.Message)"
    }

    $env:PROTON_WINDOWS_CERTIFICATE = $PfxPath
    $env:PROTON_WINDOWS_CERTIFICATE_PASSWORD = $passwordText
    $env:PROTON_WINDOWS_TIMESTAMP_URL = "none"

    Invoke-External $Moon @(
        "-C", "cli", "run", ".", "--", "-C", "../examples",
        "package", $ExampleName,
        "--config", "$ExampleName/moon.proton",
        "--sign", "--target", "app", "--target", "zip"
    )

    Require-Path $PortableDir "proton_cli package did not create the portable directory."
    Require-Path $ArchivePath "proton_cli package did not create the zip archive."

    $requiredFiles = @(
        "$ExecutableName.exe",
        "proton.dll",
        "cef_process.exe",
        "chrome_elf.dll",
        "d3dcompiler_47.dll",
        "dxcompiler.dll",
        "dxil.dll",
        "libcef.dll",
        "libEGL.dll",
        "libGLESv2.dll",
        "v8_context_snapshot.bin",
        "vk_swiftshader.dll",
        "vk_swiftshader_icd.json",
        "vulkan-1.dll",
        "chrome_100_percent.pak",
        "chrome_200_percent.pak",
        "icudtl.dat",
        "resources.pak",
        "Resources\chrome_100_percent.pak",
        "Resources\chrome_200_percent.pak",
        "Resources\icudtl.dat",
        "Resources\resources.pak",
        "Resources\locales\en-US.pak",
        "moon.proton",
        "frontend\dist\index.html",
        "proton-package.json"
    )
    foreach ($relative in $requiredFiles) {
        Require-Path (Join-Path $PortableDir $relative) "Portable layout is incomplete."
    }
    foreach ($forbidden in @("proton.lib", "libcef.lib", "bootstrap.exe", "bootstrapc.exe", "bin")) {
        if (Test-Path -LiteralPath (Join-Path $PortableDir $forbidden)) {
            Fail "Portable layout contains a build-only or CEF sample artifact: $forbidden"
        }
    }

    $ownedTargets = @(
        (Join-Path $PortableDir "$ExecutableName.exe"),
        (Join-Path $PortableDir "cef_process.exe"),
        (Join-Path $PortableDir "proton.dll")
    )
    foreach ($target in $ownedTargets) {
        Invoke-External $SignTool @("verify", "/pa", "/all", "/v", $target)
        $signature = Get-AuthenticodeSignature -LiteralPath $target
        if ($signature.Status -ne "Valid") {
            Fail "Authenticode status is not valid for $target`: $($signature.Status)"
        }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($zip.Entries.Count -eq 0) {
            Fail "Package zip is empty"
        }
    }
    finally {
        $zip.Dispose()
    }

    $ExtractRoot = Join-Path $TempRoot "Extracted App With Spaces"
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractRoot -Force
    $ExtractedPortable = Join-Path $ExtractRoot $ExecutableName
    $ExtractedExecutable = Join-Path $ExtractedPortable "$ExecutableName.exe"
    $ExpectedHelper = [IO.Path]::GetFullPath((Join-Path $ExtractedPortable "cef_process.exe"))
    Require-Path $ExtractedExecutable "Extracted package executable is missing."

    $cdpPort = Get-FreeTcpPort
    $env:PROTON_REMOTE_DEBUGGING_PORT = $cdpPort.ToString()
    $StdoutLog = Join-Path $TempRoot "app.stdout.log"
    $StderrLog = Join-Path $TempRoot "app.stderr.log"
    $AppProcess = Start-Process `
        -FilePath $ExtractedExecutable `
        -WorkingDirectory $ExtractedPortable `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $StdoutLog `
        -RedirectStandardError $StderrLog

    $page = Wait-ForCdpPage -Port $cdpPort -Process $AppProcess
    $pageUrl = [Uri]::UnescapeDataString([string]$page.url).Replace("\", "/")
    $expectedRoot = $ExtractedPortable.Replace("\", "/")
    if (-not $pageUrl.Contains("/frontend/dist/index.html")) {
        Fail "CDP page is not the packaged frontend asset: $pageUrl"
    }
    if (-not $pageUrl.Contains($expectedRoot)) {
        Fail "CDP page is not loaded from the extracted package: $pageUrl"
    }

    $helpers = Wait-ForHelpers -ParentProcessId $AppProcess.Id -ExpectedPath $ExpectedHelper
    $HelperProcessIds = @($helpers | ForEach-Object { [int]$_.ProcessId })
    Write-Output "CDP page: $pageUrl"
    Write-Output "CEF helpers: $($HelperProcessIds.Count)"

    Send-CdpBrowserClose -Port $cdpPort
    Wait-ForProcessExit -Process $AppProcess -TimeoutSeconds $ExitTimeoutSeconds
    Wait-ForHelperCleanup -ProcessIds $HelperProcessIds -TimeoutSeconds $HelperTimeoutSeconds
    $AppProcess = $null
    $HelperProcessIds = @()

    $leftovers = @(Get-ChildItem -LiteralPath $DistDir -Force | Where-Object {
        $_.Name -match "\.staging($|\.zip$)|\.backup$"
    })
    if ($leftovers.Count -gt 0) {
        Fail "Temporary package artifacts remain: $($leftovers.Name -join ', ')"
    }

    Write-Output "[OK] Windows development package smoke passed"
}
catch {
    foreach ($logPath in @($StdoutLog, $StderrLog)) {
        if ($logPath -and (Test-Path -LiteralPath $logPath)) {
            $logText = Get-Content -LiteralPath $logPath -Raw
            if ($logText) {
                Write-Error $logText.Trim()
            }
        }
    }
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    if ($AppProcess -and -not $AppProcess.HasExited) {
        try {
            Stop-Process -Id $AppProcess.Id -Force -ErrorAction Stop
        }
        catch {
            $CleanupErrors += "failed to stop app process $($AppProcess.Id): $($_.Exception.Message)"
        }
    }
    foreach ($helperId in $HelperProcessIds) {
        try {
            $helper = Get-Process -Id $helperId -ErrorAction SilentlyContinue
            if ($helper) {
                Stop-Process -Id $helperId -Force -ErrorAction Stop
            }
        }
        catch {
            $CleanupErrors += "failed to stop helper process $helperId`: $($_.Exception.Message)"
        }
    }
    if ($CertificateThumbprint) {
        try {
            Remove-CertificateFromCurrentUserRoot -Thumbprint $CertificateThumbprint
        }
        catch {
            $CleanupErrors += "failed to remove temporary Root certificate $CertificateThumbprint`: $($_.Exception.Message)"
        }
        $myCertificatePath = "Cert:\CurrentUser\My\$CertificateThumbprint"
        if (Test-Path -LiteralPath $myCertificatePath) {
            try {
                Remove-Item -LiteralPath $myCertificatePath -DeleteKey -Force -ErrorAction Stop
            }
            catch {
                $CleanupErrors += "failed to remove temporary My certificate $CertificateThumbprint`: $($_.Exception.Message)"
            }
        }
    }
    if ($Certificate) {
        $Certificate.Dispose()
    }
    if ($TempRoot -and (Test-Path -LiteralPath $TempRoot)) {
        try {
            Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction Stop
        }
        catch {
            $CleanupErrors += "failed to remove temporary directory: $($_.Exception.Message)"
        }
    }
    $env:PROTON_WINDOWS_CERTIFICATE = $OldCertificate
    $env:PROTON_WINDOWS_CERTIFICATE_PASSWORD = $OldPassword
    $env:PROTON_WINDOWS_TIMESTAMP_URL = $OldTimestamp
    $env:PROTON_REMOTE_DEBUGGING_PORT = $OldDebugPort
    if ($CleanupErrors.Count -gt 0) {
        Write-Error ($CleanupErrors -join "; ")
        exit 1
    }
}
