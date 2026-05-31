#Requires -Version 5.1
<#
.SYNOPSIS
    Find or plan platform-scoped HelpSearchServer on Mac mini.

.DESCRIPTION
    Checks Docker containers with label mcp.platform=<version>. If found and indexed,
    writes MCP_DOCS_PORT to .dev.env for reuse. Otherwise reports install needed.
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

if (-not (Test-RemoteMcpEnabled -McpHost $settings.McpHost)) {
    Write-Warning 'MCP_HOST empty or localhost — Mac docs check skipped.'
    exit 0
}

$platformPath = $settings.PlatformPath
if (-not $platformPath) {
    $detect = & (Join-Path $PSScriptRoot 'detect-platform.ps1') -ProjectRoot $ProjectRoot
    $platformPath = $detect.PlatformPath
}
$platformVersion = Split-Path $platformPath -Leaf
if (-not $platformVersion) { throw 'Cannot determine platform version from PLATFORM_PATH' }

Invoke-SshPreflight -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias

$label = "mcp.platform=$platformVersion"
$listCmd = "docker ps -a --filter `"label=$label`" --format '{{.Names}}|{{.Ports}}|{{.Status}}'"
$ps = Invoke-SshCommand -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias -RemoteCommand $listCmd

$found = $false
$port = 0
$containerName = ''
$status = 'missing'

if ($ps.Output) {
    foreach ($line in ($ps.Output -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|', 3
        $containerName = $parts[0]
        $portsField = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $status = if ($parts.Count -gt 2) { $parts[2] } else { '' }
        if ($portsField -match '0\.0\.0\.0:(\d+)->' -or $portsField -match ':(\d+)->') {
            $port = [int]$Matches[1]
            $found = $true
            break
        }
    }
}

if (-not $found) {
    $registryPath = '~/1c/mcp-registry.json'
    $readCmd = "if [ -f $registryPath ]; then cat $registryPath; else echo '{}'; fi"
    $regRaw = Invoke-SshCommand -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias -RemoteCommand $readCmd
    try {
        $reg = $regRaw.Output | ConvertFrom-Json
        if ($reg.platformDocs) {
            $docEntry = @($reg.platformDocs | Where-Object { $_.platformVersion -eq $platformVersion } | Select-Object -First 1)
            if ($docEntry) {
                $port = [int]$docEntry.port
                $containerName = $docEntry.containerName
                $found = $true
                $status = 'registry'
            }
        }
    }
    catch { }
}

$mcpId = "1C-docs-mcp-$platformVersion"
$result = [PSCustomObject]@{
    PlatformVersion = $platformVersion
    PlatformPath    = $platformPath
    McpServerId     = $mcpId
    Found           = $found
    Port            = $port
    ContainerName   = $containerName
    Status          = $status
    Action          = if ($found) { 'reuse' } else { 'install' }
}

if ($found -and $port -gt 0 -and (Test-Path $settings.DevEnvPath)) {
    Set-DevEnvKey -Path $settings.DevEnvPath -Key 'MCP_DOCS_PORT' -Value ([string]$port)
    Write-Host "Reuse $mcpId on port $port (container: $containerName)"
}
elseif (-not $found) {
    Write-Host "No indexed HelpSearchServer for platform $platformVersion — /installmcp will scp bin and create container (port >= 8100)."
}

if ($Json) { $result | ConvertTo-Json -Depth 4 }
else { return $result }
