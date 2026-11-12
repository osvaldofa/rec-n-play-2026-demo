#Requires -Version 7.0
<#
.SYNOPSIS
    Define qual loop está ativo (lido pelos hooks) ou desativa todos.
.DESCRIPTION
    Com um loop ativo, os guard rails restringem escrita de código à fase IMPLEMENT.
    Use -Desativar para trabalhar fora do loop sem interferência dos hooks.
.EXAMPLE
    ./Set-ActiveLoop.ps1 -LoopId loop-calculo-desconto
.EXAMPLE
    ./Set-ActiveLoop.ps1 -Desativar
#>
[CmdletBinding(DefaultParameterSetName = 'Ativar')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Ativar')][string]$LoopId,
    [Parameter(Mandatory, ParameterSetName = 'Desativar')][switch]$Desativar
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

if ($Desativar) {
    $anterior = Get-ActiveLoopId
    Set-ActiveLoopId $null
    if ($anterior) { Write-LoopEvent -LoopId $anterior -Acao 'LOOP_DESATIVADO' -Agente 'humano' }
    Write-LoopResult @{ ativo = $null; anterior = $anterior }
    return
}

$LoopId = Resolve-LoopId $LoopId
$state = Read-LoopState $LoopId
if ($state.status -in @('DONE', 'ABORTED')) { throw "Loop '$LoopId' está encerrado ($($state.status))." }
Set-ActiveLoopId $LoopId
Write-LoopEvent -LoopId $LoopId -Acao 'LOOP_ATIVADO' -Agente 'humano'
Write-LoopResult @{ ativo = $LoopId; status = $state.status; fase = $state.fase }
