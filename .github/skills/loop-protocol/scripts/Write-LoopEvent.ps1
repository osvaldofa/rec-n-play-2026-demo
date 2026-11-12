#Requires -Version 7.0
<#
.SYNOPSIS
    Registra um evento no log estruturado (log.jsonl) do loop.
.DESCRIPTION
    Usado pelos agentes para eventos que os hooks não capturam (decisões, desvios, premissas).
    O log narrativo detalhado vai para iteracao-NN/log-iteracao-NN.md.
.EXAMPLE
    ./Write-LoopEvent.ps1 -Acao DESVIO -Agente loop-implementer -Alvo P-02-03 -Detalhe "Usado repositório em memória"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('NOTA', 'DECISAO_AGENTE', 'DESVIO', 'BLOQUEIO', 'PREMISSA', 'ALERTA', 'ARTEFATO_GRAVADO')][string]$Acao,
    [Parameter(Mandatory)][string]$Agente,
    [string]$Alvo = '',
    [string]$Detalhe = '',
    [ValidateSet('OK', 'FALHA', 'BLOQUEADO', 'ALERTA')][string]$Resultado = 'OK',
    [string]$LoopId
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

$LoopId = Resolve-LoopId $LoopId
Write-LoopEvent -LoopId $LoopId -Acao $Acao -Agente $Agente -Alvo $Alvo -Detalhe $Detalhe -Resultado $Resultado
Write-LoopResult @{ registrado = $true; loop_id = $LoopId; acao = $Acao }
