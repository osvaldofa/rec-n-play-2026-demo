#Requires -Version 7.0
<#
.SYNOPSIS
    Fase DECIDE: mede a aderência, aplica o algoritmo de decisão e executa a transição resultante.
.DESCRIPTION
    Ordem de avaliação (seção 10 do documento base):
      1. DoD íntegra?                         não -> ESCALATED (INTEGRIDADE_DOD)
      2. CHECK verde, gates ok, índice>=limiar -> DONE (PRONTO)
      3. iteração >= max_iteracoes             -> ESCALATED (LIMITE_ITERACOES)
      4. critério planejado e não atingido
         >= max_falhas_mesmo_criterio vezes    -> ESCALATED (OSCILACAO)
      5. regressões consecutivas >= limite     -> ESCALATED (REGRESSAO)
      6. melhoria < delta_minimo por N iter.   -> ESCALATED (ESTAGNACAO)
      7. caso contrário                        -> nova iteração (PLAN)
.EXAMPLE
    ./Invoke-LoopDecision.ps1
#>
[CmdletBinding()]
param([string]$LoopId)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

$LoopId = Resolve-LoopId $LoopId
$state = Read-LoopState $LoopId
if ($state.status -ne 'EM_ANDAMENTO' -or $state.fase -ne 'VERIFY') {
    throw "A decisão só pode ocorrer após VERIFY (atual: $($state.status)/$($state.fase))."
}
$n = [int]$state.iteracao_atual
$nn = '{0:D2}' -f $n
$lim = $state.limites

$state.fase = 'DECIDE'
Save-LoopState -LoopId $LoopId -State $state
Write-LoopEvent -LoopId $LoopId -Acao 'FASE_ALTERADA' -Alvo 'DECIDE' -Detalhe 'VERIFY -> DECIDE'

$scoring = Join-Path (Get-LoopRepoRoot) '.github\skills\dod-scoring\scripts\Measure-Adherence.ps1'
$m = & $scoring -LoopId $LoopId -Iteracao $n | ConvertFrom-Json -AsHashtable
Write-LoopEvent -LoopId $LoopId -Acao 'INDICE_CALCULADO' -Agente 'dod-scoring' -Alvo "verificacao-iteracao-$nn.md" -Detalhe ("indice={0}; check={1}; gates_pendentes={2}" -f $m.indice, $m.check, ($m.gates_pendentes -join ','))

$plan = Join-Path (Get-IterationDir $LoopId $n) "planejamento-iteracao-$nn.md"
$planejados = @((Get-PlanItems $plan).Refs | Select-Object -Unique)
foreach ($id in $m.abaixo_de_um) {
    if ($id -in $planejados) {
        $atual = if ($state.falhas_por_criterio.Contains($id)) { [int]$state.falhas_por_criterio[$id] } else { 0 }
        $state.falhas_por_criterio[$id] = $atual + 1
    }
}

$historico = @($state.historico)
$anterior = if ($historico.Count -gt 0) { $historico[-1] } else { $null }
$retomada = if ($state.Contains('ponto_retomada') -and $state.ponto_retomada) { [int]$state.ponto_retomada } else { 0 }
$janelaHist = @($historico | Where-Object { [int]$_.iteracao -gt $retomada })
$alertas = [System.Collections.Generic.List[string]]::new()
foreach ($a in $m.alertas) { $alertas.Add($a) }

$regressoes = 0
if ($anterior -and [double]$m.indice -lt [double]$anterior.indice) {
    $regressoes = 1
    for ($i = $janelaHist.Count - 1; $i -ge 1; $i--) {
        if ([double]$janelaHist[$i].indice -lt [double]$janelaHist[$i - 1].indice) { $regressoes++ } else { break }
    }
    $alertas.Add(("REGRESSAO: índice caiu de {0} para {1}." -f $anterior.indice, $m.indice))
}

$estagnado = $false
$janela = [int]$lim.iteracoes_estagnacao
if ($janelaHist.Count -ge $janela) {
    $serie = @($janelaHist | Select-Object -Last $janela | ForEach-Object { [double]$_.indice }) + [double]$m.indice
    $estagnado = $true
    for ($i = 1; $i -lt $serie.Count; $i++) {
        if (($serie[$i] - $serie[$i - 1]) -ge [double]$lim.delta_minimo) { $estagnado = $false; break }
    }
    if ($estagnado) { $alertas.Add("ESTAGNACAO: melhoria abaixo de $($lim.delta_minimo) nas últimas $janela iterações.") }
}

$oscilando = @($state.falhas_por_criterio.Keys | Where-Object { [int]$state.falhas_por_criterio[$_] -ge [int]$lim.max_falhas_mesmo_criterio -and $_ -in $m.abaixo_de_um })

$decisao = 'CONTINUAR'
$motivo = $null
if (-not $m.dod_integra) { $decisao = 'ESCALAR'; $motivo = 'INTEGRIDADE_DOD' }
elseif ($m.pronto) { $decisao = 'CONCLUIR'; $motivo = 'PRONTO' }
elseif ($n -ge [int]$lim.max_iteracoes) { $decisao = 'ESCALAR'; $motivo = 'LIMITE_ITERACOES' }
elseif ($oscilando.Count -gt 0) { $decisao = 'ESCALAR'; $motivo = 'OSCILACAO'; $alertas.Add("Critérios sem convergência: $($oscilando -join ', ').") }
elseif ($regressoes -ge [int]$lim.max_regressoes_consecutivas) { $decisao = 'ESCALAR'; $motivo = 'REGRESSAO' }
elseif ($estagnado) { $decisao = 'ESCALAR'; $motivo = 'ESTAGNACAO' }

$state.historico = @($historico) + @([ordered]@{
    iteracao        = $n
    check           = $m.check
    indice          = $m.indice
    gates_pendentes = @($m.gates_pendentes)
    abaixo_de_um    = @($m.abaixo_de_um)
    decisao         = $decisao
    motivo          = $motivo
    alertas         = @($alertas)
    registrado_em   = Get-LoopTimestamp
})

$proxima = $null
switch ($decisao) {
    'CONCLUIR' {
        $state.status = 'DONE'
        $state.motivo_encerramento = $motivo
        $state.aguardando_humano = $false
        Save-LoopState -LoopId $LoopId -State $state
        Write-LoopFinalReport $state
        Write-LoopEvent -LoopId $LoopId -Acao 'DECISAO' -Alvo 'DONE' -Detalhe "motivo=$motivo; indice=$($m.indice)"
        Write-LoopEvent -LoopId $LoopId -Acao 'LOOP_ENCERRADO' -Alvo 'DONE' -Detalhe $motivo
        Set-ActiveLoopId $null
    }
    'ESCALAR' {
        Save-LoopState -LoopId $LoopId -State $state
        Write-LoopEvent -LoopId $LoopId -Acao 'DECISAO' -Alvo 'ESCALATED' -Resultado 'ALERTA' -Detalhe "motivo=$motivo; indice=$($m.indice)"
        $null = Invoke-LoopStop -LoopId $LoopId -Motivo $motivo -Fase 'DECIDE' -Detalhe ("índice {0}; gates pendentes: {1}" -f $m.indice, ($m.gates_pendentes -join ', '))
    }
    'CONTINUAR' {
        Save-LoopState -LoopId $LoopId -State $state
        Write-LoopEvent -LoopId $LoopId -Acao 'DECISAO' -Alvo 'PLAN' -Detalhe "indice=$($m.indice); gates_pendentes=$($m.gates_pendentes -join ',')"
        $state = Read-LoopState $LoopId
        $proxima = New-LoopIteration -LoopId $LoopId -State $state
    }
}
foreach ($a in $alertas) { Write-LoopEvent -LoopId $LoopId -Acao 'ALERTA' -Resultado 'ALERTA' -Detalhe $a }

$final = Read-LoopState $LoopId
Write-LoopResult @{
    loop_id          = $LoopId
    iteracao         = $n
    decisao          = $decisao
    motivo           = $motivo
    status           = $final.status
    fase             = $final.fase
    proxima_iteracao = $proxima
    indice           = $m.indice
    limiar           = $m.limiar
    check            = $m.check
    gates_pendentes  = @($m.gates_pendentes)
    abaixo_de_um     = @($m.abaixo_de_um)
    alertas          = @($alertas)
}
