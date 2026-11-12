#Requires -Version 7.0
<#
.SYNOPSIS
    Calcula o índice de aderência de uma iteração a partir da DoD congelada e da verificação.
.DESCRIPTION
    - Pesos e gates vêm SEMPRE da DoD (02-definicao-de-pronto.md), nunca da verificação.
    - Pontuações aceitas: 0, 0,5 e 1. Valor inválido, ausente ou sem evidência => 0.
    - Status do CHECK é lido de checagem-iteracao-NN.md ("Status geral: VERDE|VERMELHO").
    - Confere a integridade da DoD (hash SHA-256 registrado na aprovação).
    Saída: JSON com índice, gates pendentes, critérios abaixo de 1, status de pronto e alertas.
.EXAMPLE
    ./Measure-Adherence.ps1 -LoopId loop-calculo-desconto -Iteracao 2
#>
[CmdletBinding()]
param(
    [string]$LoopId,
    [int]$Iteracao
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\loop-protocol\scripts\LoopCommon.psm1') -Force

$LoopId = Resolve-LoopId $LoopId
$state = Read-LoopState $LoopId
if (-not $PSBoundParameters.ContainsKey('Iteracao')) { $Iteracao = [int]$state.iteracao_atual }
if ($Iteracao -lt 1) { throw 'Nenhuma iteração para medir.' }
$nn = '{0:D2}' -f $Iteracao
$iterDir = Get-IterationDir $LoopId $Iteracao
$dir = Get-LoopDir $LoopId

$alertas = [System.Collections.Generic.List[string]]::new()

$dodPath = Join-Path $dir '02-definicao-de-pronto.md'
$dodIntegra = $true
if ($state.dod.congelada) {
    $atual = Get-FileSha256 $dodPath
    if ($atual -ne $state.dod.hash_sha256) {
        $dodIntegra = $false
        $alertas.Add('INTEGRIDADE: o hash da DoD difere do registrado na aprovação.')
    }
}

$criterios = Get-DodCriteria $LoopId

$verPath = Join-Path $iterDir "verificacao-iteracao-$nn.md"
if (-not (Test-Path $verPath)) { throw "Verificação não encontrada: $verPath" }
$pontuacoes = @{}
foreach ($t in (Get-MarkdownTables $verPath)) {
    $colId = @('criterio', 'id') | Where-Object { $_ -in $t.Headers } | Select-Object -First 1
    if (-not $colId -or 'pontuacao' -notin $t.Headers) { continue }
    foreach ($r in $t.Rows) {
        $id = ($r[$colId] -replace '\*', '').Trim()
        if ($id -match '^((?:DOD|PT)-\d{2,})\b') { $id = $Matches[1] } else { continue }
        $pontuacoes[$id] = $r
    }
}

$detalhes = [System.Collections.Generic.List[object]]::new()
$somaPesos = 0.0
$somaPontos = 0.0
$gatesPendentes = [System.Collections.Generic.List[string]]::new()
$abaixo = [System.Collections.Generic.List[string]]::new()

foreach ($c in $criterios.Values) {
    $score = 0.0
    $obs = ''
    if (-not $pontuacoes.ContainsKey($c.id)) {
        $obs = 'não avaliado'
        $alertas.Add("$($c.id) não foi avaliado na verificação (pontuação 0).")
    } else {
        $r = $pontuacoes[$c.id]
        $v = ConvertTo-LoopNumber $r['pontuacao']
        $evid = if ($r.ContainsKey('evidencia')) { [string]$r['evidencia'] } else { '' }
        if ($null -eq $v -or $v -notin @(0.0, 0.5, 1.0)) {
            $obs = "pontuação inválida '$($r['pontuacao'])'"
            $alertas.Add("$($c.id): pontuação inválida '$($r['pontuacao'])' (considerada 0).")
        } elseif ($v -gt 0 -and ($evid.Trim() -eq '' -or $evid.Trim() -match '^(-|n/?a|<.*>)$')) {
            $obs = 'sem evidência'
            $alertas.Add("$($c.id): pontuação $v sem evidência (considerada 0).")
        } else {
            $score = [double]$v
        }
    }
    $somaPesos += $c.peso
    $somaPontos += $c.peso * $score
    if ($score -lt 1) {
        $abaixo.Add($c.id)
        if ($c.gate) { $gatesPendentes.Add($c.id) }
    }
    $detalhes.Add([ordered]@{ id = $c.id; peso = $c.peso; gate = $c.gate; pontuacao = $score; observacao = $obs })
}
foreach ($k in $pontuacoes.Keys) { if (-not $criterios.Contains($k)) { $alertas.Add("$k está na verificação mas não existe na DoD (ignorado).") } }

$check = 'DESCONHECIDO'
$chkPath = Join-Path $iterDir "checagem-iteracao-$nn.md"
if (Test-Path $chkPath) {
    $m = Select-String -Path $chkPath -Pattern '^\s*\**Status geral\**\s*:\s*\**\s*(VERDE|VERMELHO)\b'
    if ($m) { $check = $m.Matches[0].Groups[1].Value }
}
if ($check -ne 'VERDE') { $alertas.Add("CHECK = $check.") }

$indice = if ($somaPesos -gt 0) { [math]::Round($somaPontos / $somaPesos, 4) } else { 0 }
$limiar = [double]$state.limites.limiar_aderencia
$pronto = ($check -eq 'VERDE') -and ($gatesPendentes.Count -eq 0) -and ($indice -ge $limiar) -and $dodIntegra

[ordered]@{
    loop_id         = $LoopId
    iteracao        = $Iteracao
    indice          = $indice
    limiar          = $limiar
    check           = $check
    dod_integra     = $dodIntegra
    pronto          = $pronto
    gates_pendentes = @($gatesPendentes)
    abaixo_de_um    = @($abaixo)
    soma_pesos      = $somaPesos
    soma_pontos     = $somaPontos
    detalhes        = @($detalhes)
    alertas         = @($alertas)
} | ConvertTo-Json -Depth 6
