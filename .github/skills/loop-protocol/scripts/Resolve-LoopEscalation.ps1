#Requires -Version 7.0
<#
.SYNOPSIS
    Decisão humana sobre um loop parado: retomar do ponto de parada (Continuar) ou encerrar (Abortar).
.DESCRIPTION
    O humano não avalia iterações: apenas decide, diante de uma condição de parada, se o loop
    recomeça e com qual orçamento/orientação.
    D-17 (contrato imutável após o GATE_DOD):
      - a orientação (-Motivo) é técnica (ambiente, dependências, abordagem) e nunca altera regra,
        critério ou teste congelado — em conflito, prevalece a DoD;
      - paradas por motivo de contrato (AMBIGUIDADE_REGRA, CONTESTACAO_CRITERIO, CONTESTACAO_TESTE)
        não admitem Continuar: aborte e inicie um novo loop com Initialize-Loop.ps1 -LoopAnterior;
      - Continuar exige que 00/01/02 tenham o hash aprovado.
    Retomada (Continuar):
      - parado em DECIDE (iteração já avaliada) -> abre a próxima iteração em PLAN
        (amplia max_iteracoes se o limite foi atingido);
      - parado no meio de uma fase (PLAN, IMPLEMENT, CHECK, VERIFY, REFINE) -> volta para a mesma
        fase da mesma iteração (em IMPLEMENT, o escopo de escrita é recalculado a partir do plano).
      - zera os contadores de oscilação; estagnação/regressão passam a considerar só iterações
        posteriores à última iteração avaliada.
.EXAMPLE
    ./Resolve-LoopEscalation.ps1 -Decisao Continuar -AutorizadoPor osvaldofa -IteracoesExtras 2 -Motivo "SDK instalado; usar repositório em memória nos testes"
.EXAMPLE
    ./Resolve-LoopEscalation.ps1 -Decisao Abortar -AutorizadoPor osvaldofa -Motivo "Spec será revista"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Continuar', 'Abortar')][string]$Decisao,
    [Parameter(Mandatory)][string]$AutorizadoPor,
    [string]$LoopId,
    [ValidateRange(1, 10)][int]$IteracoesExtras = 1,
    [string]$Motivo = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

$LoopId = Resolve-LoopId $LoopId
$state = Read-LoopState $LoopId

if ($Decisao -eq 'Abortar') {
    if ($state.status -in @('DONE', 'ABORTED')) { throw "Loop '$LoopId' já está encerrado ($($state.status))." }
    $state.status = 'ABORTED'
    $state.motivo_encerramento = 'ABORTADO_PELO_USUARIO'
    $state.aguardando_humano = $false
    $state.escopo_escrita_atual = @()
    Save-LoopState -LoopId $LoopId -State $state
    Write-LoopEvent -LoopId $LoopId -Acao 'LOOP_ENCERRADO' -Agente 'humano' -Alvo 'ABORTED' -Detalhe "por $AutorizadoPor; $Motivo"
    if ((Get-ActiveLoopId) -eq $LoopId) { Set-ActiveLoopId $null }
    Write-LoopResult @{ loop_id = $LoopId; status = 'ABORTED'; motivo = $Motivo }
    return
}

if ($state.status -ne 'ESCALATED') { throw "Só é possível retomar um loop parado (ESCALATED); atual: $($state.status)." }

# D-17: regras de negócio, critérios e testes congelados não mudam no mesmo loop.
if ($state.motivo_encerramento -in $MotivosContrato) {
    throw ("D-17: a parada '{0}' envolve o contrato aprovado (regra de negócio, critério ou teste congelado) e não admite retomada neste loop. " +
           "Aborte (-Decisao Abortar) e inicie um novo loop a partir da spec refinada revisada: Initialize-Loop.ps1 -Nome <nome-v2> -LoopAnterior {1} -SpecText '<decisão sobre a regra>'.") -f $state.motivo_encerramento, $LoopId
}
$divergentes = Get-LoopContractDivergence -LoopId $LoopId -State $state
if ($divergentes.Count) {
    throw ("D-17: artefatos congelados alterados desde a aprovação da DoD: {0}. Restaure o conteúdo aprovado (ex.: git) para retomar, ou aborte e inicie um novo loop com -LoopAnterior {1}." -f ($divergentes -join ', '), $LoopId)
}

$parada = if ($state.Contains('parada') -and $state.parada) { $state.parada } else { [ordered]@{ fase = 'DECIDE'; iteracao = [int]$state.iteracao_atual; motivo = $state.motivo_encerramento; detalhe = '' } }
$faseParada = [string]$parada.fase
$n = [int]$state.iteracao_atual
$anteriorMax = [int]$state.limites.max_iteracoes
$atingiuLimite = ($faseParada -eq 'DECIDE' -and $n -ge $anteriorMax)
if ($atingiuLimite -or $PSBoundParameters.ContainsKey('IteracoesExtras')) {
    $state.limites.max_iteracoes = [math]::Max($anteriorMax, $n + $IteracoesExtras)
}

$escopo = @()
if ($faseParada -eq 'IMPLEMENT') {
    $escopo = Get-PlanWriteScope (Join-Path (Get-IterationDir $LoopId $n) ("planejamento-iteracao-{0:D2}.md" -f $n))
}

$ultimaAvaliada = @($state.historico | ForEach-Object { [int]$_.iteracao }) | Measure-Object -Maximum | ForEach-Object Maximum
$registro = [ordered]@{
    fase          = $faseParada
    iteracao      = [int]$parada.iteracao
    motivo        = $parada.motivo
    detalhe       = $parada.detalhe
    retomado_por  = $AutorizadoPor
    orientacao    = $Motivo
    retomado_em   = Get-LoopTimestamp
}
$state.paradas = @(if ($state.Contains('paradas')) { $state.paradas }) + @($registro)
$state.parada = $null
$state.status = 'EM_ANDAMENTO'
$state.motivo_encerramento = $null
$state.aguardando_humano = $false
$state.falhas_por_criterio = [ordered]@{}
$state.ponto_retomada = [int]($ultimaAvaliada ?? 0)
if ($Motivo) { $state.alertas += "[it $n] Retomada após $($parada.motivo) por ${AutorizadoPor}: $Motivo" }

$destino = $faseParada
if ($faseParada -ne 'DECIDE') {
    $state.fase = $faseParada
    $state.escopo_escrita_atual = $escopo
}
Save-LoopState -LoopId $LoopId -State $state
Set-ActiveLoopId $LoopId
Write-LoopEvent -LoopId $LoopId -Acao 'ESCALONAMENTO_RESOLVIDO' -Agente 'humano' -Alvo 'CONTINUAR' -Detalhe ("parada={0}@it{1} ({2}); max_iteracoes {3}->{4}; por {5}; {6}" -f $faseParada, $parada.iteracao, $parada.motivo, $anteriorMax, $state.limites.max_iteracoes, $AutorizadoPor, $Motivo)

if ($faseParada -eq 'DECIDE') {
    $state = Read-LoopState $LoopId
    $n = New-LoopIteration -LoopId $LoopId -State $state
    $destino = 'PLAN'
}

Write-LoopResult @{
    loop_id        = $LoopId
    status         = 'EM_ANDAMENTO'
    fase           = $destino
    iteracao       = $n
    retomado_de    = "$faseParada (iteração $($parada.iteracao))"
    max_iteracoes  = $state.limites.max_iteracoes
    escopo_escrita = @($escopo)
}
