#Requires -Version 7.0
<#
.SYNOPSIS
    Hook de observabilidade: registra eventos do ciclo de vida no log.jsonl do loop ativo
    e injeta contexto do loop em sessões e subagentes.
.PARAMETER Evento
    sessionStart | sessionEnd | postToolUse | postToolUseFailure | subagentStart | subagentStop
.NOTES
    Nunca bloqueia: qualquer erro resulta em saída vazia ({}).
    Não registra conteúdo de argumentos/resultados (apenas alvo resumido) para evitar dados sensíveis.
#>
param([Parameter(Mandatory)][string]$Evento)
if (-not (Test-Path (Join-Path $PSScriptRoot '..\..\..\loops\.active'))) { [Console]::Out.Write('{}'); exit 0 }
$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'HookCommon.psm1') -Force
    $evt = Read-HookInput
    $loopId = Get-ActiveLoopId
    if (-not $loopId) { Write-HookOutput @{}; exit 0 }
    $state = Read-LoopState $loopId
    $agente = Get-HookAgent $evt

    function Get-LoopContext {
        $nn = '{0:D2}' -f [int]$state.iteracao_atual
        $base = "loops/$loopId"
        $linhas = @(
            "[loop-harness] Loop ativo: $loopId",
            "- Status: $($state.status) | Fase: $($state.fase) | Iteração: $($state.iteracao_atual)/$($state.limites.max_iteracoes) | Limiar: $($state.limites.limiar_aderencia)",
            "- DoD: $(if ($state.dod.congelada) { "v$($state.dod.versao) congelada (hash $($state.dod.hash_sha256.Substring(0,12)))" } else { 'em elaboração' })",
            "- Artefatos: $base/00-spec-original.md, $base/01-spec-refinada.md, $base/02-definicao-de-pronto.md"
        )
        if ([int]$state.iteracao_atual -gt 0) { $linhas += "- Iteração corrente: $base/iteracao-$nn/" }
        if (@($state.escopo_escrita_atual).Count) { $linhas += "- Escopo de escrita: $(@($state.escopo_escrita_atual) -join ', ')" }
        $linhas += "- Próxima ação do protocolo: $(Get-LoopNextAction $state)"
        $linhas -join "`n"
    }

    switch ($Evento) {
        'sessionStart' {
            Write-LoopEvent -LoopId $loopId -Acao 'SESSAO_INICIO' -Agente $agente -Detalhe ([string](Get-HookValue $evt @('source')))
            Write-HookOutput @{ additionalContext = (Get-LoopContext) + "`n- Para continuar o loop use /loop-resume; para consultar use /loop-status." }
        }
        'sessionEnd' {
            Write-LoopEvent -LoopId $loopId -Acao 'SESSAO_FIM' -Agente $agente -Detalhe ([string](Get-HookValue $evt @('reason')))
            Write-HookOutput @{}
        }
        'postToolUse' {
            $tool = Get-HookToolName $evt
            $targs = Get-HookToolArgs $evt
            $alvo = (Get-HookToolPaths $targs) -join ', '
            if (-not $alvo) { $alvo = Get-HookCommand $targs }
            Write-LoopEvent -LoopId $loopId -Acao 'FERRAMENTA_EXECUTADA' -Agente $agente -Alvo (Format-HookTarget $alvo) -Detalhe $tool
            Write-HookOutput @{}
        }
        'postToolUseFailure' {
            $tool = Get-HookToolName $evt
            $targs = Get-HookToolArgs $evt
            $alvo = (Get-HookToolPaths $targs) -join ', '
            if (-not $alvo) { $alvo = Get-HookCommand $targs }
            $erro = [string](Get-HookValue $evt @('error'))
            Write-LoopEvent -LoopId $loopId -Acao 'FERRAMENTA_FALHOU' -Agente $agente -Alvo (Format-HookTarget $alvo) -Resultado 'FALHA' -Detalhe ("{0}: {1}" -f $tool, (Format-HookTarget $erro 300))
            Write-HookOutput @{}
        }
        'subagentStart' {
            $nome = [string](Get-HookValue $evt @('agentName', 'agent_name', 'agentDisplayName'))
            Write-LoopEvent -LoopId $loopId -Acao 'SUBAGENTE_INICIO' -Agente $nome -Alvo $nome
            if ($nome -notmatch '(?i)loop-') { Write-HookOutput @{}; exit 0 }
            $ctx = Get-LoopContext
            if ($state.status -ne 'EM_ANDAMENTO') {
                $ctx += "`n`nBLOQUEADO PELO HARNESS: o loop está em $($state.status). Não execute nenhuma ação; responda apenas 'BLOQUEADO_PELO_HARNESS: loop em $($state.status)'."
            } elseif ([int]$state.iteracao_atual -gt [int]$state.limites.max_iteracoes) {
                $ctx += "`n`nBLOQUEADO PELO HARNESS: limite de iterações excedido. Responda apenas 'BLOQUEADO_PELO_HARNESS: limite de iterações'."
            }
            Write-HookOutput @{ additionalContext = $ctx }
        }
        'subagentStop' {
            $nome = [string](Get-HookValue $evt @('agentName', 'agent_name', 'agentDisplayName'))
            $resp = [string](Get-HookValue $evt @('response', 'last_assistant_message'))
            $duracao = $null
            $logPath = Join-Path (Get-LoopDir $loopId) 'log.jsonl'
            $inicio = Get-Content $logPath -Tail 400 -Encoding utf8 | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } |
                Where-Object { $_.acao -eq 'SUBAGENTE_INICIO' -and $_.alvo -eq $nome } | Select-Object -Last 1
            if ($inicio) {
                $t = $inicio.ts
                if ($t -isnot [datetime]) { $t = [datetimeoffset]::Parse([string]$t, [System.Globalization.CultureInfo]::InvariantCulture).LocalDateTime }
                $duracao = [long]((Get-Date) - $t).TotalMilliseconds
            }
            Write-LoopEvent -LoopId $loopId -Acao 'SUBAGENTE_FIM' -Agente $nome -Alvo $nome -DuracaoMs $duracao -Detalhe "resposta: $($resp.Length) caracteres"
            Write-HookOutput @{}
        }
        default { Write-HookOutput @{} }
    }
} catch {
    [Console]::Out.Write('{}')
}
exit 0
