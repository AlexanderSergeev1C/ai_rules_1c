#Requires -Version 5.1
<#
.SYNOPSIS
    Sync configuration dump and metadata report from Windows to Mac mini MCP host.

.DESCRIPTION
    Copies EXPORT_PATH (or project root) to code-{ProjectName}/ and sibling
    {ProjectName}_report/ to metadata-{ProjectName}/ via scp + SSH config.
    See content/rules/sync-to-mcp-host.md and /synctomcp.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [switch]$SkipReport,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'mcp-remote-common.ps1')

if (-not $ProjectRoot) { $ProjectRoot = Find-ProjectRoot }
$settings = Get-RemoteMcpSettings -ProjectRoot $ProjectRoot

if (-not (Test-RemoteMcpEnabled -McpHost $settings.McpHost)) {
    Write-Warning 'MCP_HOST empty or localhost — remote sync skipped (upstream single-machine mode).'
    exit 0
}

$configXml = Join-Path $settings.ExportPath 'Configuration.xml'
$configExt = Join-Path $settings.ExportPath 'ConfigurationExtension.xml'
if (-not ((Test-Path $configXml) -or (Test-Path $configExt))) {
    throw "Configuration dump not found in $($settings.ExportPath) (expected Configuration.xml or ConfigurationExtension.xml)"
}

Write-Host "SSH preflight: $($settings.SshHostAlias) via $($settings.SshConfig)"
if (-not $WhatIf) {
    Invoke-SshPreflight -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias
    $mkdirCmd = "mkdir -p '$($settings.RemoteCodePath)' '$($settings.RemoteMetadataPath)'"
    $mk = Invoke-SshCommand -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias -RemoteCommand $mkdirCmd
    if ($mk.ExitCode -ne 0) { throw "mkdir on Mac failed: $($mk.Output)" }
}

$results = @()

Write-Host "Sync code: $($settings.ExportPath) -> $($settings.RemoteCodePath)"
if ($WhatIf) {
    Write-Host '  [WhatIf] scp skipped'
}
else {
    $codeResult = Invoke-ScpSync -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias `
        -LocalPath (Join-Path $settings.ExportPath '*') -RemotePath $settings.RemoteCodePath
    $results += [PSCustomObject]@{
        Kind      = 'code'
        Remote    = $settings.RemoteCodePath
        ExitCode  = $codeResult.ExitCode
        Files     = $codeResult.FileCount
        SizeBytes = $codeResult.SizeBytes
        Elapsed   = $codeResult.Elapsed.ToString()
        Stderr    = $codeResult.Output
    }
    if ($codeResult.ExitCode -ne 0) {
        Write-Error "Code sync failed (exit $($codeResult.ExitCode)): $($codeResult.Output)"
    }
}

if (-not $SkipReport) {
    if (Test-Path $settings.ReportDir) {
        Write-Host "Sync report: $($settings.ReportDir) -> $($settings.RemoteMetadataPath)"
        if ($WhatIf) {
            Write-Host '  [WhatIf] scp skipped'
        }
        else {
            $metaResult = Invoke-ScpSync -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias `
                -LocalPath (Join-Path $settings.ReportDir '*') -RemotePath $settings.RemoteMetadataPath
            $results += [PSCustomObject]@{
                Kind      = 'metadata'
                Remote    = $settings.RemoteMetadataPath
                ExitCode  = $metaResult.ExitCode
                Files     = $metaResult.FileCount
                SizeBytes = $metaResult.SizeBytes
                Elapsed   = $metaResult.Elapsed.ToString()
                Stderr    = $metaResult.Output
            }
            if ($metaResult.ExitCode -ne 0) {
                Write-Error "Report sync failed (exit $($metaResult.ExitCode)): $($metaResult.Output)"
            }
        }
    }
    else {
        Write-Warning "Report folder not found: $($settings.ReportDir) — metadata sync skipped (non-blocking)."
    }
}

Write-Host ''
Write-Host 'Sync summary:'
foreach ($r in $results) {
    $sizeMb = [math]::Round($r.SizeBytes / 1MB, 2)
    Write-Host ("  {0,-10} exit={1} files={2} size={3} MB elapsed={4}" -f $r.Kind, $r.ExitCode, $r.Files, $sizeMb, $r.Elapsed)
}

return $results
