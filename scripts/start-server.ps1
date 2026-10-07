<#
.SYNOPSIS
  Start the campus router web demo from Windows. The server runs inside WSL, because the
  routing engine is a Linux program.

.DESCRIPTION
  - Builds the engine if needed.
  - Photo import needs an Anthropic API key. If ANTHROPIC_API_KEY is not already set, you are
    asked for it (typing is hidden); press Enter to skip photo import. The key is handed to
    WSL for this run only and is never written to disk.
  - Stops an older copy of the server if one is still running.

.EXAMPLE
  .\scripts\start-server.ps1
  powershell -ExecutionPolicy Bypass -File .\scripts\start-server.ps1   # if scripts are blocked
#>
param(
    [string]$Distro = "Ubuntu",
    [int]$Port = 8000,
    [switch]$NoKeyPrompt
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "WSL isn't installed. The router needs it: https://learn.microsoft.com/windows/wsl/install"
}

# ---- API key (only used for photo import) ----
if (-not $env:ANTHROPIC_API_KEY -and -not $NoKeyPrompt) {
    $secure = Read-Host "Anthropic API key for photo import (press Enter to skip)" -AsSecureString
    if ($secure.Length -gt 0) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $env:ANTHROPIC_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}
if ($env:ANTHROPIC_API_KEY) {
    # /u: share this variable with WSL only when starting WSL from Windows (as we do here)
    $env:WSLENV = (@($env:WSLENV, "ANTHROPIC_API_KEY/u") | Where-Object { $_ }) -join ":"
    Write-Host "Photo import: key found. It is passed to WSL for this run only and is not saved."
    # Ask Anthropic whether it accepts the key (a free call), so a bad key is caught now,
    # not when you press the photo button. The key itself is never printed, only its ends.
    & wsl.exe -d $Distro --cd $repo -- python3 server/check_key.py
} else {
    Write-Host "Photo import: skipped (no key). Everything else works."
}

# ---- stop an old server, then start a new one ----
& wsl.exe -d $Distro -- pkill -f "[s]erver/server.py" 2>$null | Out-Null

Write-Host "Starting the server. Open http://localhost:$Port  (Ctrl+C to stop)"
& wsl.exe -d $Distro --cd $repo -- bash -c "make -C engine route > /dev/null && exec python3 server/server.py --port $Port"
