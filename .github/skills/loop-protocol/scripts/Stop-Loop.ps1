#Requires -Version 7.0
<#
.SYNOPSIS
    Dispara uma condição de parada a partir do próprio loop (sem aprovação humana no meio do ciclo).
.DESCRIPTION
    Usado pelo orquestrador quando o loop não consegue prosseguir de forma autônoma.
    O loop vai para ESCALATED e registra o ponto exato de parada (fase e iteração).
    Motivos operacionais (retomáveis do ponto de parada com Resolve-LoopEscalation -Decisao Continuar):
      IMPEDIMENTO       ambiente/SDK ausente, dependência externa indisponível
      FALHA_PROTOCOLO   script ou subagente falhou após 2 tentativas
    Motivos de contrato (D-17: sem retomada no mesmo loop; abortar e abrir novo loop com DoD v2):
      AMBIGUIDADE_REGRA     a spec/DoD não define uma regra de negócio necessária para prosseguir
      CONTESTACAO_CRITERIO  um critério da DoD é contraditório ou impossível de atender
.EXAMPLE
    ./Stop-Loop.ps1 -Motivo IMPEDIMENTO -Agente loop-orchestrator -Detalhe "Build falha por SDK ausente no ambiente"
.EXAMPLE
    ./Stop-Loop.ps1 -Motivo AMBIGUIDADE_REGRA -Detalhe "RN-02 não define o arredondamento do desconto (FL-03)"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('IMPEDIMENTO', 'FALHA_PROTOCOLO', 'AMBIGUIDADE_REGRA', 'CONTESTACAO_CRITERIO')][string]$Motivo,
    [Parameter(Mandatory)][string]$Detalhe,
    [string]$Agente = 'loop-orchestrator',
    [string]$LoopId
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

$LoopId = Resolve-LoopId $LoopId
$state = Read-LoopState $LoopId
if ($state.fase -eq 'GATE_DOD') { throw 'No GATE_DOD o loop já aguarda o humano; não há o que parar.' }
$state = Invoke-LoopStop -LoopId $LoopId -Motivo $Motivo -Detalhe $Detalhe -Agente $Agente

Write-LoopResult @{
    loop_id = $LoopId
    status  = $state.status
    parada  = $state.parada
}
