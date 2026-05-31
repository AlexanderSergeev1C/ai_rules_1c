#Requires -Version 5.1
<#
.SYNOPSIS
    Detect 1C platform installation on Windows and update PLATFORM_PATH in .dev.env.

.DESCRIPTION
    Scans C:\Program Files\1cv8\ (and x86) for installed platforms, picks the best
    match for PLATFORM_VERSION from .dev.env (CompatibilityMode), writes PLATFORM_PATH.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'mcp-remote-common.ps1')

if (-not $ProjectRoot) { $ProjectRoot = Find-ProjectRoot }
$settings = Get-RemoteMcpSettings -ProjectRoot $ProjectRoot
$candidates = Find-PlatformInstallations

if ($candidates.Count -eq 0) {
    Write-Error 'No 1C platform installations found under Program Files\1cv8'
}

$preferred = $settings.PlatformVersion
$selected = $null
if ($preferred -and $preferred -match '^\d+(\.\d+){1,3}$') {
    $selected = $candidates | Where-Object {
        $_.Version.StartsWith($preferred + '.') -or $_.Version -eq $preferred
    } | Select-Object -First 1
}
if (-not $selected) { $selected = $candidates | Select-Object -First 1 }

$binPath = Join-Path $selected.Path 'bin'
if ($settings.DevEnvPath -and (Test-Path $settings.DevEnvPath)) {
    Set-DevEnvKey -Path $settings.DevEnvPath -Key 'PLATFORM_PATH' -Value $selected.Path
    if (-not $settings.PlatformVersion) {
        Set-DevEnvKey -Path $settings.DevEnvPath -Key 'PLATFORM_VERSION' -Value ($selected.Version -replace '\.\d+$', '')
    }
}

$result = [PSCustomObject]@{
    PlatformPath    = $selected.Path
    PlatformVersion = $selected.Version
    BinPath         = $binPath
    AllInstallations = $candidates | ForEach-Object { $_.Version }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 4
}
else {
    Write-Host "PLATFORM_PATH = $($selected.Path)"
    Write-Host "Version       = $($selected.Version)"
    Write-Host "Bin           = $binPath"
}

return $result
