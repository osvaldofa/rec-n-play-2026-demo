#Requires -Version 7.0
<#
.SYNOPSIS
    Hook preToolUse: aplica os guard rails do loop ativo (G-01, G-06..G-11).
.DESCRIPTION
    Sem loop ativo (loops/.active), retorna {} e não interfere.
    Ferramentas de escrita:
      - caminhos protegidos do harness/estado            -> deny
      - spec refinada/DoD após congelamento              -> deny
      - configurações de cobertura existentes após DoD   -> deny
      - iterações fechadas ou ainda não abertas          -> deny
      - código fora de loops/ fora da fase IMPLEMENT     -> deny
      - código fora do escopo de escrita do plano        -> deny
    Comandos de shell:
      - padrões bloqueados / remoção recursiva fora da allowlist -> deny
      - escrita em arquivos protegidos via shell                -> deny
      - padrões restritos (rede, instalação global, variáveis de sistema):
          loop em andamento -> deny (nenhuma aprovação humana no meio do ciclo)
          loop parado       -> ask
    Erros inesperados em ferramentas de escrita/shell resultam em deny (fail-closed).
#>
if (-not (Test-Path (Join-Path $PSScriptRoot '..\..\..\loops\.active'))) { [Console]::Out.Write('{}'); exit 0 }

$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'HookCommon.psm1') -Force
} catch {
    $active = Join-Path $PSScriptRoot '..\..\..\loops\.active'
    if (Test-Path $active) {
        [Console]::Out.Write((@{ permissionDecision = 'deny'; permissionDecisionReason = "[loop-guardrails] Harness indisponível com loop ativo (fail-closed): $($_.Exception.Message). Corrija o harness ou remova loops/.active manualmente." } | ConvertTo-Json -Compress))
    } else { [Console]::Out.Write('{}') }
    exit 0
}

$evt = Read-HookInput
$toolName = Get-HookToolName $evt
$toolArgs = Get-HookToolArgs $evt

$isShell = Test-HookIsShellTool $toolName $toolArgs
$isWrite = (-not $isShell) -and (Test-HookIsWriteTool $toolName)
if ($isWrite -and $toolName -match '(?i)str_replace_editor' -and $toolArgs -is [System.Collections.IDictionary] -and $toolArgs.Contains('command') -and $toolArgs['command'] -eq 'view') { $isWrite = $false }
if (-not $isShell -and -not $isWrite) { Write-HookOutput @{}; exit 0 }

$loopId = $null
try {
    $loopId = Get-ActiveLoopId
    if (-not $loopId) { Write-HookOutput @{}; exit 0 }
    $state = Read-LoopState $loopId
    if ($state.status -in @('DONE', 'ABORTED')) { Write-HookOutput @{}; exit 0 }

    $cfg = Get-LoopConfig
    $agente = Get-HookAgent $evt
    $cwd = Get-HookCwd $evt
    $emAndamento = $state.status -eq 'EM_ANDAMENTO'
    $congelada = [bool]$state.dod.congelada
    $iter = [int]$state.iteracao_atual

    function Deny([string]$Motivo, [string]$Alvo) {
        Write-LoopEvent -LoopId $loopId -Acao 'GUARDRAIL_BLOQUEIO' -Agente $agente -Alvo (Format-HookTarget $Alvo) -Resultado 'BLOQUEADO' -Detalhe "$toolName`: $Motivo"
        Write-HookOutput @{ permissionDecision = 'deny'; permissionDecisionReason = "[loop-guardrails] $Motivo" }
        exit 0
    }
    function Ask([string]$Motivo, [string]$Alvo) {
        Write-LoopEvent -LoopId $loopId -Acao 'GUARDRAIL_CONFIRMACAO' -Agente $agente -Alvo (Format-HookTarget $Alvo) -Resultado 'CONFIRMACAO' -Detalhe "$toolName`: $Motivo"
        Write-HookOutput @{ permissionDecision = 'ask'; permissionDecisionReason = "[loop-guardrails] $Motivo" }
        exit 0
    }

    if ($isWrite) {
        $paths = Get-HookToolPaths $toolArgs
        if ($paths.Count -eq 0) { Write-HookOutput @{}; exit 0 }
        foreach ($p in $paths) {
            $rel = ConvertTo-LoopRelativePath -Path $p -BaseDir $cwd
            if ([System.IO.Path]::IsPathRooted($rel)) {
                if ($emAndamento) { Deny "Escrita fora do repositório não é permitida durante o loop ($rel)." $rel }
                continue
            }
            if (Test-LoopGlob $rel $cfg.caminhos_protegidos) {
                Deny "'$rel' é protegido pelo harness. Estado, log e spec original só mudam via scripts do protocolo (.github/skills/loop-protocol/scripts)." $rel
            }
            if ($congelada -and (Test-LoopGlob $rel $cfg.caminhos_protegidos_apos_dod)) {
                Deny "'$rel' está congelado desde a aprovação da DoD (v$($state.dod.versao)). Alterações exigem nova aprovação humana." $rel
            }
            if ($congelada -and (Test-LoopGlob $rel $cfg.configuracoes_cobertura) -and (Test-Path (Join-Path (Get-LoopRepoRoot) $rel))) {
                Deny "'$rel' é configuração de cobertura/qualidade e não pode ser alterada após a aprovação da DoD (PT-04/PT-14)." $rel
            }
            if ($rel -match '^loops/([^/]+)/(.*)$') {
                $alvoLoop = $Matches[1]; $resto = $Matches[2]
                if ($alvoLoop -ne $loopId) { Deny "'$rel' pertence a outro loop ($alvoLoop); o loop ativo é $loopId." $rel }
                if ($resto -match '^iteracao-(\d+)(/|$)') {
                    $alvoIter = [int]$Matches[1]
                    if ($alvoIter -lt $iter) { Deny "A iteração $alvoIter está fechada e é imutável (iteração atual: $iter)." $rel }
                    if ($alvoIter -gt $iter) { Deny "A iteração $alvoIter ainda não foi aberta. Iterações são abertas apenas pelos scripts do protocolo (limite: $($state.limites.max_iteracoes))." $rel }
                }
                continue
            }
            if ($rel -match '^loops(/|$)') { continue }
            if ($emAndamento) {
                if ($state.fase -ne 'IMPLEMENT') { Deny "A fase atual é $($state.fase); alterações de código só são permitidas na fase IMPLEMENT ('$rel')." $rel }
                if (-not (Test-LoopGlob $rel @($state.escopo_escrita_atual))) {
                    Deny "'$rel' está fora do escopo de escrita da iteração $iter ($(@($state.escopo_escrita_atual) -join ', ')). Registre o desvio no log da iteração e trate no próximo plano." $rel
                }
            }
        }
        Write-HookOutput @{}
        exit 0
    }

    $cmd = Get-HookCommand $toolArgs
    if (-not $cmd) { Write-HookOutput @{}; exit 0 }

    foreach ($rx in $cfg.comandos_bloqueados) {
        if ($cmd -match "(?i)$rx") { Deny "Comando bloqueado pelo harness (padrão: $rx)." $cmd }
    }

    $rm = [regex]::Matches($cmd, '(?i)\b(Remove-Item|rm|rmdir|rd|del|erase|ri)\b[^;|&\r\n]*')
    foreach ($m in $rm) {
        $seg = $m.Value
        if ($seg -match '(?i)(\s-Recurse\b|\s-r\b|\s-rf\b|\s-fr\b|\s/s\b)') {
            $alvos = [regex]::Matches($seg, '(?i)[\w\.\-/\\:\*]+') | ForEach-Object Value | Where-Object { $_ -notmatch '^(?i)(Remove-Item|rm|rmdir|rd|del|erase|ri|-\w+|/\w)$' }
            $permitidos = @($cfg.remocao_recursiva_permitida)
            $ok = @($alvos).Count -gt 0
            foreach ($a in $alvos) {
                $ultimo = (($a -replace '\\', '/').TrimEnd('/', '*') -split '/')[-1]
                if ($ultimo -notin $permitidos) { $ok = $false }
            }
            if (-not $ok) { Deny "Remoção recursiva permitida apenas para: $($permitidos -join ', ')." $seg }
        }
    }

    $invocaProtocolo = $cmd -match '(?i)\.github[\\/]+skills[\\/]+(loop-protocol|dod-scoring)[\\/]+scripts[\\/]+[\w\-]+\.ps1'
    if (-not $invocaProtocolo) {
        $tokens = @('loop-state.json', 'log.jsonl', 'loops/.active', 'loops\.active', '00-spec-original.md', '.github/hooks', '.github\hooks', 'loop-config.json', 'loop-protocol/scripts', 'loop-protocol\scripts', 'dod-scoring/scripts', 'dod-scoring\scripts')
        if ($congelada) { $tokens += @('01-spec-refinada.md', '02-definicao-de-pronto.md') }
        $verbos = '(?i)(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Move-Item|Copy-Item|Rename-Item|Clear-Content|WriteAll|AppendAll|\btee\b|\bsed\s+-i|\bmv\b|\bcp\b|\brm\b|\bdel\b|\bren\b|(?<![<>=-])>{1,2}(?!=))'
        foreach ($t in $tokens) {
            if ($cmd.IndexOf($t, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $cmd -match $verbos) {
                Deny "Escrita via shell em artefato protegido ('$t'). Use os scripts do protocolo." $cmd
            }
        }
    }

    foreach ($rx in $cfg.comandos_restritos) {
        if ($cmd -match "(?i)$rx") {
            if ($emAndamento) { Deny "Comando restrito durante o loop (padrão: $rx). Nenhuma aprovação humana ocorre no meio do ciclo: use uma alternativa local ou, se for indispensável, dispare a parada com Stop-Loop.ps1 -Motivo IMPEDIMENTO." $cmd }
            Ask "Comando restrito: o loop está parado ($($state.status)); confirme a execução (padrão: $rx)." $cmd
        }
    }

    Write-HookOutput @{}
    exit 0
} catch {
    $msg = $_.Exception.Message
    try { if ($loopId) { Write-LoopEvent -LoopId $loopId -Acao 'GUARDRAIL_ERRO' -Agente 'hook' -Alvo $toolName -Resultado 'FALHA' -Detalhe (Format-HookTarget $msg 300) } } catch { }
    Write-HookOutput @{ permissionDecision = 'deny'; permissionDecisionReason = "[loop-guardrails] Falha ao avaliar guard rails (fail-closed): $msg" }
    exit 0
}
