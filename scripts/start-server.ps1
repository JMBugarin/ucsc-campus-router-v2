<#
.SYNOPSIS
  Start the campus router web demo from Windows. The server runs inside WSL, because the
  routing engine is a Linux program.

.DESCRIPTION
  - Builds the engine if needed.
  - Stops an older copy of the server if one is still running.

.EXAMPLE
  .\scripts\start-server.ps1
  powershell -ExecutionPolicy Bypass -File .\scripts\start-server.ps1   # if scripts are blocked
#>
param(
    [string]$Distro = "Ubuntu",
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "WSL isn't installed. The router needs it: https://learn.microsoft.com/windows/wsl/install"
}

# ---- stop an old server, then start a new one ----
& wsl.exe -d $Distro -- pkill -f "[s]erver/server.py" 2>$null | Out-Null

Write-Host "Starting the server. Open http://localhost:$Port  (Ctrl+C to stop)"
& wsl.exe -d $Distro --cd $repo -- bash -c "make -C engine route > /dev/null && exec python3 server/server.py --port $Port"
