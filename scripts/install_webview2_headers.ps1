param(
  [string]$Version = $(if ($env:WEBVIEW2_SDK_VERSION) { $env:WEBVIEW2_SDK_VERSION } else { "1.0.3967.48" }),
  [string]$IncludeDir = "build\_deps\microsoft_web_webview2-src\build\native\include"
)

$ErrorActionPreference = "Stop"

if (-not $Version.Trim()) {
  throw "WebView2 SDK version must not be empty."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$resolvedIncludeDir = Join-Path $repoRoot $IncludeDir
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("lepus-webview2-" + [System.Guid]::NewGuid().ToString("N"))
$archive = Join-Path $workDir "webview2.zip"
$extractDir = Join-Path $workDir "webview2"
$sourceIncludeDir = Join-Path $extractDir "build\native\include"
$packageUrl = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$Version"

New-Item -ItemType Directory -Force -Path $workDir | Out-Null

try {
  Write-Host "Downloading Microsoft.Web.WebView2 $Version"
  Invoke-WebRequest -Uri $packageUrl -OutFile $archive
  Expand-Archive -Path $archive -DestinationPath $extractDir -Force

  if (-not (Test-Path (Join-Path $sourceIncludeDir "WebView2.h"))) {
    throw "Downloaded WebView2 SDK did not contain build\native\include\WebView2.h."
  }

  New-Item -ItemType Directory -Force -Path $resolvedIncludeDir | Out-Null
  Copy-Item -Path (Join-Path $sourceIncludeDir "*") -Destination $resolvedIncludeDir -Recurse -Force

  Write-Host "Installed WebView2 SDK headers to $resolvedIncludeDir"
} finally {
  Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
