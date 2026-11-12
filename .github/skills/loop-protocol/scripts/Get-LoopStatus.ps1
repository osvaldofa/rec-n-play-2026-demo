#Requires -Version 7.0
<#
.SYNOPSIS
    Resume o estado de um loop (ou lista todos os loops) com curva de convergência e próxima ação.
.EXAMPLE
    ./Get-LoopStatus.ps1
.EXAMPLE
    ./Get-LoopStatus.ps1 -LoopId loop-calculo-desconto -Formato Json
.EXAMPLE
    ./Get-LoopStatus.ps1 -Todos
#>
[CmdletBinding()]
param(
    [string]$LoopId,
    [ValidateSet('Markdown', 'Json')][string]$Formato = 'Markdown',
    [switch]$Todos
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

function Format-Indice($v) { if ($null -eq $v) { '-' } else { ('{0:0.00}' -f [double]$v).Replace('.', ',') } }

$ativo = Get-ActiveLoopId
if ($Todos -or (-not $LoopId -and -not $ativo)) {
    $loops = @(Get-ChildItem (Get-LoopsRoot) -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'loop-state.json') } | ForEach-Object {
            $s = Read-LoopState $_.Name
            $ult = if (@($s.historico).Count) { @($s.historico)[-1].indice } else { $null }
            [ordered]@{ loop_id = $s.loop_id; status = $s.status; fase = $s.fase; iteracao = $s.iteracao_atual; indice = $ult; ativo = ($s.loop_id -eq $ativo); atualizado_em = $s.atualizado_em }
        })
    if ($Formato -eq 'Json') { return (@{ ativo = $ativo; loops = $loops } | ConvertTo-Json -Depth 5) }
    if (-not $loops) { return 'Nenhum loop encontrado em loops/. Inicie um com /loop-start.' }
    $out = @('| Loop | Status | Fase | Iteração | Índice | Ativo | Atualizado em |', '|---|---|---|---|---|---|---|')
    $out += $loops | ForEach-Object { '| {0} | {1} | {2} | {3} | {4} | {5} | {6} |' -f $_.loop_id, $_.status, $_.fase, $_.iteracao, (Format-Indice $_.indice), ($(if ($_.ativo) { 'sim' } else { '' })), $_.atualizado_em }
    return ($out -join "`n")
}

$LoopId = Resolve-LoopId $LoopId
$s = Read-LoopState $LoopId
$logPath = Join-Path (Get-LoopDir $LoopId) 'log.jsonl'
$eventos = @(if (Test-Path $logPath) { Get-Content $logPath -Encoding utf8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } })
$bloqueios = @($eventos | Where-Object { $_.resultado -eq 'BLOQUEADO' })
$hist = @($s.historico)
$ultimo = if ($hist.Count) { $hist[-1] } else { $null }
$proxima = Get-LoopNextAction $s

if ($Formato -eq 'Json') {
    return ([ordered]@{
            loop_id           = $s.loop_id
            ativo             = ($LoopId -eq $ativo)
            status            = $s.status
            fase              = $s.fase
            iteracao          = $s.iteracao_atual
            max_iteracoes     = $s.limites.max_iteracoes
            aguardando_humano = $s.aguardando_humano
            dod               = $s.dod
            historico         = $hist
            gates_pendentes   = if ($ultimo) { @($ultimo.gates_pendentes) } else { @() }
            eventos           = $eventos.Count
            bloqueios         = $bloqueios.Count
            proxima_acao      = $proxima
            motivo            = $s.motivo_encerramento
            parada            = if ($s.Contains('parada')) { $s.parada } else { $null }
            paradas           = if ($s.Contains('paradas')) { @($s.paradas) } else { @() }
        } | ConvertTo-Json -Depth 8)
}

$md = [System.Collections.Generic.List[string]]::new()
$md.Add("## Status — $($s.loop_id)")
$md.Add('')
$md.Add('| Campo | Valor |')
$md.Add('|---|---|')
$md.Add("| Status | **$($s.status)**$(if ($s.motivo_encerramento) { " ($($s.motivo_encerramento))" }) |")
$md.Add("| Fase | $($s.fase) |")
$md.Add("| Iteração | $($s.iteracao_atual) / $($s.limites.max_iteracoes) |")
$md.Add("| Limiar | $(Format-Indice $s.limites.limiar_aderencia) |")
$md.Add("| Aguardando humano | $(if ($s.aguardando_humano) { 'sim' } else { 'não' }) |")
if ($s.Contains('parada') -and $s.parada) { $md.Add("| Ponto de parada | $($s.parada.fase), iteração $($s.parada.iteracao) — $($s.parada.motivo): $($s.parada.detalhe) |") }
if ($s.Contains('paradas') -and @($s.paradas).Count) { $md.Add("| Retomadas | $(@($s.paradas).Count) |") }
$md.Add("| DoD | $(if ($s.dod.congelada) { "v$($s.dod.versao) congelada por $($s.dod.aprovada_por) em $($s.dod.aprovada_em)" } else { 'em elaboração' }) |")
$md.Add("| Eventos no log | $($eventos.Count) ($($bloqueios.Count) bloqueios de guard rail) |")
$md.Add("| Loop ativo | $(if ($LoopId -eq $ativo) { 'sim' } else { 'não' }) |")
$md.Add('')
if ($hist.Count) {
    $md.Add('### Curva de convergência')
    $md.Add('')
    $md.Add('| Iteração | Check | Índice | Gates pendentes | Decisão |')
    $md.Add('|---|---|---|---|---|')
    foreach ($h in $hist) { $md.Add(('| {0} | {1} | {2} | {3} | {4}{5} |' -f $h.iteracao, $h.check, (Format-Indice $h.indice), (@($h.gates_pendentes) -join ', '), $h.decisao, $(if ($h.motivo) { " ($($h.motivo))" } else { '' }))) }
    $md.Add('')
}
$alertas = @($s.alertas | Select-Object -Last 5)
if ($alertas) {
    $md.Add('### Últimos alertas')
    $md.Add('')
    foreach ($a in $alertas) { $md.Add("- $a") }
    $md.Add('')
}
if ($bloqueios) {
    $md.Add('### Últimos bloqueios de guard rail')
    $md.Add('')
    foreach ($b in ($bloqueios | Select-Object -Last 5)) { $md.Add("- $($b.ts) · $($b.agente) · $($b.alvo) — $($b.detalhe)") }
    $md.Add('')
}
$md.Add("**Próxima ação:** $proxima")
$md -join "`n"
