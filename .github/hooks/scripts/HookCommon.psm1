#Requires -Version 7.0
# Utilitários dos hooks: leitura do payload (stdin), extração de caminhos/comandos e saída JSON.

Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '..\..\skills\loop-protocol\scripts\LoopCommon.psm1') -Force -Global

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

function Read-HookInput {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    try { $raw | ConvertFrom-Json -AsHashtable -Depth 50 } catch { @{} }
}

function Write-HookOutput {
    param([System.Collections.IDictionary]$Data = @{})
    [Console]::Out.Write(($Data | ConvertTo-Json -Depth 10 -Compress))
}

function Get-HookValue {
    param([System.Collections.IDictionary]$Event, [string[]]$Keys)
    foreach ($k in $Keys) { if ($Event -and $Event.Contains($k) -and $null -ne $Event[$k] -and "$($Event[$k])" -ne '') { return $Event[$k] } }
    $null
}

function Get-HookToolName {
    param([System.Collections.IDictionary]$Event)
    [string](Get-HookValue $Event @('toolName', 'tool_name'))
}

function Get-HookToolArgs {
    param([System.Collections.IDictionary]$Event)
    $a = Get-HookValue $Event @('toolArgs', 'tool_input', 'toolInput')
    if ($a -is [string]) {
        try { return ($a | ConvertFrom-Json -AsHashtable -Depth 50) } catch { return @{ input = $a } }
    }
    if ($null -eq $a) { return @{} }
    $a
}

function Get-HookAgent {
    param([System.Collections.IDictionary]$Event)
    $n = Get-HookValue $Event @('agentName', 'agent_name', 'agentType', 'agent_type')
    if ($n) { [string]$n } else { 'principal' }
}

function Get-HookCwd {
    param([System.Collections.IDictionary]$Event)
    $c = Get-HookValue $Event @('cwd')
    if ($c -and (Test-Path $c)) { [string]$c } else { Get-LoopRepoRoot }
}

$script:PathKeys = @('path', 'filePath', 'file_path', 'filename', 'fileName', 'file', 'target_file', 'targetFile', 'new_path', 'newPath', 'old_path', 'oldPath', 'destination', 'source', 'uri', 'notebook_path')
$script:PathListKeys = @('paths', 'files', 'filePaths', 'file_paths')

function Get-HookToolPaths {
    param($ToolArgs)
    $paths = [System.Collections.Generic.List[string]]::new()
    if ($ToolArgs -is [System.Collections.IDictionary]) {
        foreach ($k in $script:PathKeys) {
            if ($ToolArgs.Contains($k) -and $ToolArgs[$k] -is [string] -and $ToolArgs[$k]) { $paths.Add($ToolArgs[$k]) }
        }
        foreach ($k in $script:PathListKeys) {
            if ($ToolArgs.Contains($k)) { foreach ($p in @($ToolArgs[$k])) { if ($p -is [string] -and $p) { $paths.Add($p) } elseif ($p -is [System.Collections.IDictionary]) { foreach ($x in (Get-HookToolPaths $p)) { $paths.Add($x) } } } }
        }
        foreach ($k in 'input', 'patch', 'diff') {
            if ($ToolArgs.Contains($k) -and $ToolArgs[$k] -is [string]) {
                foreach ($m in [regex]::Matches($ToolArgs[$k], '(?m)^\*\*\*\s+(?:Add|Update|Delete)\s+File:\s*(.+?)\s*$|^\*\*\*\s+Move to:\s*(.+?)\s*$')) {
                    $v = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
                    if ($v) { $paths.Add($v) }
                }
            }
        }
        foreach ($k in 'edits', 'changes', 'operations') {
            if ($ToolArgs.Contains($k)) { foreach ($e in @($ToolArgs[$k])) { if ($e -is [System.Collections.IDictionary]) { foreach ($x in (Get-HookToolPaths $e)) { $paths.Add($x) } } } }
        }
    }
    @($paths | Select-Object -Unique)
}

function Get-HookCommand {
    param($ToolArgs)
    if ($ToolArgs -is [System.Collections.IDictionary]) {
        foreach ($k in 'command', 'cmd', 'script', 'commandLine') { if ($ToolArgs.Contains($k) -and $ToolArgs[$k] -is [string]) { return $ToolArgs[$k] } }
    }
    $null
}

function Test-HookIsShellTool {
    param([string]$ToolName, $ToolArgs)
    if ($ToolName -match '(?i)^(bash|powershell|pwsh|shell|sh|cmd|terminal|execute|run_in_terminal|runInTerminal|Bash)$') { return $true }
    $false
}

function Test-HookIsWriteTool {
    param([string]$ToolName)
    if ($ToolName -match '(?i)(^|_)(view|read|grep|glob|search|list|find|fetch|get)(_|$)') { return $false }
    $ToolName -match '(?i)(edit|create|write|apply_patch|str_replace|replace|insert|delete|remove|rename|move|notebook|Write|Edit|MultiEdit)'
}

function Format-HookTarget {
    param([string]$Text, [int]$Max = 160)
    if (-not $Text) { return '' }
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Max) { $t.Substring(0, $Max) + '…' } else { $t }
}

Export-ModuleMember -Function *
