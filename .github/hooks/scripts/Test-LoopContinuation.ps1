#Requires -Version 7.0
<#
.SYNOPSIS
    Hook agentStop (escopo do loop-orchestrator): impede que o orquestrador encerre o turno
    enquanto o loop está em andamento e não aguarda decisão humana.
.DESCRIPTION
    - Bloqueia o fim do turno com uma instrução de continuidade (decision = block).
    - Libera em GATE_DOD, ESCALATED, DONE, ABORTED ou quando autonomia.continuar_automaticamente = false.
    - Proteção contra laço: após 3 bloqueios consecutivos na mesma fase/iteração, dispara a condição
      de parada ORQUESTRADOR_INTERROMPIDO (ESCALATED); o humano retoma do ponto de parada.
#>
if (-not (Test-Path (Join-Path $PSScriptRoot '..\..\..\loops\.active'))) { [Console]::Out.Write('{}'); exit 0 }

$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'HookCommon.psm1') -Force
    $null = Read-HookInput
    $loopId = Get-ActiveLoopId
    if (-not $loopId) { Write-HookOutput @{}; exit 0 }
    $state = Read-LoopState $loopId
    $cfg = Get-LoopConfig
    if (-not $cfg.autonomia.continuar_automaticamente -or $state.status -ne 'EM_ANDAMENTO' -or $state.aguardando_humano -or $state.fase -eq 'GATE_DOD') {
        Write-HookOutput @{}; exit 0
    }

    $marcador = Join-Path (Get-LoopDir $loopId) '.continuacao.json'
    $chave = "$($state.fase)|$($state.iteracao_atual)"
    $cont = @{ chave = ''; bloqueios = 0 }
    if (Test-Path $marcador) { try { $cont = Get-Content $marcador -Raw | ConvertFrom-Json -AsHashtable } catch { } }
    $bloqueios = if ($cont.chave -eq $chave) { [int]$cont.bloqueios + 1 } else { 1 }

    if ($bloqueios -gt 3) {
        Remove-Item $marcador -Force -ErrorAction SilentlyContinue
        $null = Invoke-LoopStop -LoopId $loopId -Motivo 'ORQUESTRADOR_INTERROMPIDO' -Agente 'hook' -Detalhe "O orquestrador encerrou o turno 3 vezes seguidas na fase $($state.fase) sem avançar o protocolo."
        Write-HookOutput @{}; exit 0
    }
    [System.IO.File]::WriteAllText($marcador, (@{ chave = $chave; bloqueios = $bloqueios } | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))

    Write-LoopEvent -LoopId $loopId -Acao 'CONTINUIDADE_FORCADA' -Agente 'hook' -Alvo $state.fase -Detalhe "tentativa $bloqueios/3"
    $reason = "[loop-harness] O loop $loopId está em andamento (fase $($state.fase), iteração $($state.iteracao_atual)/$($state.limites.max_iteracoes)). " +
              "Nenhuma aprovação humana ocorre no meio do ciclo: não faça perguntas ao usuário, continue o protocolo a partir da fase atual. Próxima ação: $(Get-LoopNextAction $state) " +
              "Só encerre o turno em GATE_DOD, ESCALATED, DONE ou ABORTED. Se o loop realmente não puder prosseguir, dispare a parada com Stop-Loop.ps1 -Motivo IMPEDIMENTO -Detalhe '<causa>'."
    Write-HookOutput @{ decision = 'block'; reason = $reason }
} catch {
    [Console]::Out.Write('{}')
}
exit 0
