# Shared helpers for remote MCP host workflow (Windows → Mac mini).
# Dot-source from tools/*.ps1: . (Join-Path $PSScriptRoot 'mcp-remote-common.ps1')

function Read-DevEnvFile {
    param([string]$Path)
    $result = [ordered]@{}
    if (-not (Test-Path $Path)) { return $result }
    foreach ($line in (Get-Content -Path $Path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $trim = $line.TrimStart()
        if ($trim.StartsWith('#')) { continue }
        if ($trim -match '^([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$') {
            $result[$Matches[1]] = $Matches[2]
        }
    }
    return $result
}

function Get-DevEnvValue {
    param(
        [System.Collections.IDictionary]$Keys,
        [string]$Key,
        [string]$Default = ''
    )
    if ($Keys.Contains($Key) -and -not [string]::IsNullOrWhiteSpace([string]$Keys[$Key])) {
        return [string]$Keys[$Key].Trim()
    }
    return $Default
}

function Find-ProjectRoot {
    param([string]$StartDir = (Get-Location).Path)
    $dir = $StartDir
    while ($dir) {
        if ((Test-Path (Join-Path $dir '.dev.env')) -or
            (Test-Path (Join-Path $dir 'Configuration.xml')) -or
            (Test-Path (Join-Path $dir 'ConfigurationExtension.xml'))) {
            return $dir
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $StartDir
}

function Get-RemoteMcpSettings {
    param([string]$ProjectRoot)
    $envPath = Join-Path $ProjectRoot '.dev.env'
    $keys = Read-DevEnvFile -Path $envPath
    $projectName = Split-Path $ProjectRoot -Leaf
    $exportPath = Get-DevEnvValue -Keys $keys -Key 'EXPORT_PATH'
    if (-not $exportPath) { $exportPath = $ProjectRoot }
    elseif (-not [System.IO.Path]::IsPathRooted($exportPath)) {
        $exportPath = Join-Path $ProjectRoot $exportPath
    }

    $sshConfig = Get-DevEnvValue -Keys $keys -Key 'MCP_SSH_CONFIG' -Default "$env:USERPROFILE\.ssh\config"
    $hostAlias = Get-DevEnvValue -Keys $keys -Key 'MCP_SSH_HOST_ALIAS' -Default 'mac-mini'
    $syncBase = Get-DevEnvValue -Keys $keys -Key 'MCP_SYNC_BASE' -Default '/Users/al/1c/sync'
    $codeSuffix = Get-DevEnvValue -Keys $keys -Key 'MCP_SYNC_CODE_SUFFIX' -Default 'code-'
    $metaSuffix = Get-DevEnvValue -Keys $keys -Key 'MCP_SYNC_METADATA_SUFFIX' -Default 'metadata-'
    $reportSuffix = Get-DevEnvValue -Keys $keys -Key 'METADATA_REPORT_SUFFIX' -Default '_report'
    $mcpHost = Get-DevEnvValue -Keys $keys -Key 'MCP_HOST'
    $parentDir = Split-Path $ProjectRoot -Parent
    $reportDir = Join-Path $parentDir ($projectName + $reportSuffix)

    return [PSCustomObject]@{
        DevEnvPath         = $envPath
        Keys               = $keys
        ProjectRoot        = $ProjectRoot
        ProjectName        = $projectName
        ExportPath         = $exportPath
        ReportDir          = $reportDir
        McpHost            = $mcpHost
        SshConfig          = $sshConfig
        SshHostAlias       = $hostAlias
        SyncBase           = $syncBase.TrimEnd('/')
        RemoteCodePath     = "$($syncBase.TrimEnd('/'))/$codeSuffix$projectName/"
        RemoteMetadataPath = "$($syncBase.TrimEnd('/'))/$metaSuffix$projectName/"
        PortBase           = Get-DevEnvValue -Keys $keys -Key 'MCP_PORT_BASE'
        DocsPort           = Get-DevEnvValue -Keys $keys -Key 'MCP_DOCS_PORT'
        ImageTag           = Get-DevEnvValue -Keys $keys -Key 'MCP_IMAGE_TAG' -Default 'arm64'
        PlatformPath       = Get-DevEnvValue -Keys $keys -Key 'PLATFORM_PATH'
        PlatformVersion    = Get-DevEnvValue -Keys $keys -Key 'PLATFORM_VERSION'
    }
}

function Test-RemoteMcpEnabled {
    param([string]$McpHost)
    if ([string]::IsNullOrWhiteSpace($McpHost)) { return $false }
    $h = $McpHost.Trim().ToLowerInvariant()
    return ($h -ne 'localhost' -and $h -ne '127.0.0.1')
}

function Invoke-SshPreflight {
    param(
        [string]$SshConfig,
        [string]$HostAlias
    )
    $args = @('-F', $SshConfig, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', $HostAlias, 'echo ok')
    $output = & ssh @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SSH preflight failed for Host $HostAlias (config: $SshConfig): $output"
    }
    return $true
}

function Invoke-SshCommand {
    param(
        [string]$SshConfig,
        [string]$HostAlias,
        [string]$RemoteCommand
    )
    $args = @('-F', $SshConfig, $HostAlias, $RemoteCommand)
    $output = & ssh @args 2>&1
    return @{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String).Trim()
    }
}

function Invoke-ScpSync {
    param(
        [string]$SshConfig,
        [string]$HostAlias,
        [string]$LocalPath,
        [string]$RemotePath
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $args = @('-F', $SshConfig, '-r', "$LocalPath", "${HostAlias}:$RemotePath")
    $output = & scp @args 2>&1
    $sw.Stop()
    $fileCount = 0
    $sizeBytes = 0
    if (Test-Path $LocalPath) {
        $items = Get-ChildItem -Path $LocalPath -Recurse -File -ErrorAction SilentlyContinue
        $fileCount = @($items).Count
        $sizeBytes = ($items | Measure-Object -Property Length -Sum).Sum
        if (-not $sizeBytes) { $sizeBytes = 0 }
    }
    return [PSCustomObject]@{
        ExitCode  = $LASTEXITCODE
        Output    = ($output | Out-String).Trim()
        Elapsed   = $sw.Elapsed
        FileCount = $fileCount
        SizeBytes = $sizeBytes
    }
}

function Set-DevEnvKey {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )
    if (-not (Test-Path $Path)) { throw ".dev.env not found: $Path" }
    $text = Get-Content -Path $Path -Raw -Encoding UTF8
    $pattern = '(?m)^' + [regex]::Escape($Key) + '=.*$'
    $escVal = $Value -replace '\$', '$$$$'
    if ($text -match $pattern) {
        $text = [regex]::Replace($text, $pattern, ($Key + '=' + $escVal), 1)
    }
    else {
        $text = $text.TrimEnd() + "`n$key=$Value`n"
    }
    Set-Content -Path $Path -Value $text -Encoding UTF8 -NoNewline
}

function Find-PlatformInstallations {
    $roots = @()
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $pf) { continue }
        $r = Join-Path $pf '1cv8'
        if (Test-Path $r) { $roots += $r }
    }
    $candidates = @()
    foreach ($r in $roots) {
        Get-ChildItem -Directory -Path $r -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+){2,3}$' -and (Test-Path (Join-Path $_.FullName 'bin\1cv8.exe')) } |
            ForEach-Object {
                $verParts = ($_.Name -split '\.') | ForEach-Object { [int]$_ }
                while ($verParts.Count -lt 4) { $verParts += 0 }
                $candidates += [PSCustomObject]@{
                    Path    = $_.FullName
                    Version = $_.Name
                    SortKey = ($verParts[0] * 1000000000L) + ($verParts[1] * 1000000L) + ($verParts[2] * 1000L) + $verParts[3]
                }
            }
    }
    return @($candidates | Sort-Object SortKey -Descending)
}
