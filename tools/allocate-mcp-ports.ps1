#Requires -Version 5.1
<#
.SYNOPSIS
    Allocate a per-project MCP port pool on Mac mini and update .dev.env + registry.

.DESCRIPTION
    Each project gets MCP_PORT_BASE .. MCP_PORT_BASE+9 (8000-8009, 8010-8019, …).
    Registry: ~/1c/mcp-registry.json on Mac. Reuses existing pool if project alive.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'mcp-remote-common.ps1')

if (-not $ProjectRoot) { $ProjectRoot = Find-ProjectRoot }
$settings = Get-RemoteMcpSettings -ProjectRoot $ProjectRoot

if (-not (Test-RemoteMcpEnabled -McpHost $settings.McpHost)) {
    Write-Warning 'MCP_HOST empty or localhost — port allocation skipped.'
    exit 0
}

Invoke-SshPreflight -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias

$registryPath = '~/1c/mcp-registry.json'
$readCmd = @"
if [ -f $registryPath ]; then cat $registryPath; else echo '{"projects":[]}'; fi
"@
$regRaw = Invoke-SshCommand -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias -RemoteCommand $readCmd
if ($regRaw.ExitCode -ne 0) { throw "Failed to read registry: $($regRaw.Output)" }

try {
    $registry = $regRaw.Output | ConvertFrom-Json
}
catch {
    $registry = [PSCustomObject]@{ projects = @() }
}
if (-not $registry.projects) { $registry | Add-Member -NotePropertyName projects -NotePropertyValue @() }

$projectName = $settings.ProjectName
$existing = @($registry.projects | Where-Object { $_.projectName -eq $projectName } | Select-Object -First 1)
$portBase = 0

if ($existing -and -not $Force -and $settings.PortBase -match '^\d+$') {
    $portBase = [int]$settings.PortBase
    Write-Host "Reuse MCP_PORT_BASE=$portBase for project $projectName (from .dev.env)"
}
elseif ($existing -and -not $Force) {
    $portBase = [int]$existing.portBase
    Set-DevEnvKey -Path $settings.DevEnvPath -Key 'MCP_PORT_BASE' -Value ([string]$portBase)
    Write-Host "Reuse registry MCP_PORT_BASE=$portBase for project $projectName"
}
else {
    $usedBases = @($registry.projects | ForEach-Object { [int]$_.portBase })
    $dockerPs = Invoke-SshCommand -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias `
        -RemoteCommand "docker ps --format '{{.Ports}}'"
    $portBase = 8000
    while ($true) {
        if ($usedBases -contains $portBase) {
            $portBase += 10
            continue
        }
        $rangeEnd = $portBase + 9
        $inUse = $false
        if ($dockerPs.Output) {
            for ($p = $portBase; $p -le $rangeEnd; $p++) {
                if ($dockerPs.Output -match ":$p->" -or $dockerPs.Output -match "0\.0\.0\.0:$p" -or $dockerPs.Output -match "\[$p\]:") {
                    $inUse = $true
                    break
                }
            }
        }
        if (-not $inUse) { break }
        $portBase += 10
        if ($portBase -gt 8990) { throw 'No free port decade found (8000-8990 exhausted)' }
    }

    $entry = [ordered]@{
        projectName = $projectName
        portBase    = $portBase
        assignedAt  = (Get-Date).ToUniversalTime().ToString('o')
    }
    $newProjects = @($registry.projects | Where-Object { $_.projectName -ne $projectName })
    $newProjects += [PSCustomObject]$entry
    $registryObj = @{ projects = $newProjects }
    $json = $registryObj | ConvertTo-Json -Depth 5 -Compress
    $jsonEsc = $json -replace "'", "'\\''"
    $writeCmd = "mkdir -p ~/1c && printf '%s' '$jsonEsc' > $registryPath"
    $wr = Invoke-SshCommand -SshConfig $settings.SshConfig -HostAlias $settings.SshHostAlias -RemoteCommand $writeCmd
    if ($wr.ExitCode -ne 0) { throw "Failed to write registry: $($wr.Output)" }

    Set-DevEnvKey -Path $settings.DevEnvPath -Key 'MCP_PORT_BASE' -Value ([string]$portBase)
    Write-Host "Allocated MCP_PORT_BASE=$portBase (range $portBase-$($portBase + 9)) for project $projectName"
}

$result = [PSCustomObject]@{
    ProjectName = $projectName
    PortBase    = $portBase
    PortRange   = "$portBase-$($portBase + 9)"
}
return $result
