#Requires -Version 7.0
<#
.SYNOPSIS
    Executa uma transição de fase validada do loop.
.DESCRIPTION
    Transições suportadas por este script:
      REFINE    -> GATE_DOD   (valida spec refinada, DoD e comandos técnicos)
      GATE_DOD  -> REFINE     (ajustes solicitados pelo humano; exige -Motivo)
      PLAN      -> IMPLEMENT  (valida checklist, limite de itens e escopo de escrita)
      IMPLEMENT -> CHECK      (exige todos os itens marcados)
      CHECK     -> VERIFY     (exige checagem registrada)
    Aprovação da DoD: Approve-LoopDod.ps1. Decisão pós-verificação: Invoke-LoopDecision.ps1.
    Escalonamento/aborto: Resolve-LoopEscalation.ps1.
.EXAMPLE
    ./Set-LoopPhase.ps1 -Fase IMPLEMENT
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('GATE_DOD', 'REFINE', 'IMPLEMENT', 'CHECK', 'VERIFY')][string]$Fase,
    [string]$LoopId,
    [string]$Motivo = '',
    [switch]$PermitirPendentes
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

$LoopId = Resolve-LoopId $LoopId
$state = Read-LoopState $LoopId
$dir = Get-LoopDir $LoopId
if ($state.status -ne 'EM_ANDAMENTO') { throw "Loop '$LoopId' não está em andamento (status $($state.status))." }

$permitidas = @{
    'REFINE'    = @('GATE_DOD')
    'GATE_DOD'  = @('REFINE')
    'PLAN'      = @('IMPLEMENT')
    'IMPLEMENT' = @('CHECK')
    'CHECK'     = @('VERIFY')
}
$atual = $state.fase
if (-not $permitidas.ContainsKey($atual) -or $Fase -notin $permitidas[$atual]) {
    throw "Transição inválida: $atual -> $Fase."
}

$n = [int]$state.iteracao_atual
$nn = '{0:D2}' -f $n
$iterDir = if ($n -gt 0) { Get-IterationDir $LoopId $n } else { $null }
$detalhe = "$atual -> $Fase"
$alertas = [System.Collections.Generic.List[string]]::new()

switch ($Fase) {
    'GATE_DOD' {
        $spec = Join-Path $dir '01-spec-refinada.md'
        if (-not (Test-Path $spec)) { throw 'Spec refinada não encontrada.' }
        $pend = Select-String -Path $spec, (Join-Path $dir '02-definicao-de-pronto.md') -Pattern '<preencher' -SimpleMatch
        if ($pend) { throw ("Há marcadores '<preencher' não resolvidos: " + (($pend | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }) -join ', ')) }
        $criterios = Get-DodCriteria $LoopId
        $ids = @($criterios.Keys)
        if (-not ($ids | Where-Object { $_ -like 'DOD-*' })) { throw 'A DoD não possui critérios funcionais (DOD-xx).' }
        foreach ($pt in 'PT-01', 'PT-03', 'PT-04', 'PT-05') { if ($pt -notin $ids) { throw "Padrão técnico obrigatório ausente na DoD: $pt." } }
        $state.aguardando_humano = $true
    }
    'REFINE' {
        if ([string]::IsNullOrWhiteSpace($Motivo)) { throw 'Informe -Motivo com os ajustes solicitados.' }
        $state.aguardando_humano = $false
        $detalhe = "$detalhe; motivo: $Motivo"
    }
    'IMPLEMENT' {
        $plan = Join-Path $iterDir "planejamento-iteracao-$nn.md"
        $items = Get-PlanItems $plan
        if ($items.Count -eq 0) { throw "O plano não contém itens de checklist no formato '- [ ] P-$nn-01 ...'." }
        $max = [int]$state.limites.max_itens_por_plano
        if ($items.Count -gt $max) { throw "O plano tem $($items.Count) itens; o máximo é $max." }
        $invalidos = @($items | Where-Object { $_.Id -notlike "P-$nn-*" })
        if ($invalidos) { throw "Itens com ID fora do padrão P-$nn-xx: $(($invalidos.Id) -join ', ')" }
        $semRef = @($items | Where-Object { $_.Refs.Count -eq 0 })
        if ($semRef) { throw "Itens sem referência a critério da DoD (DOD-xx/PT-xx): $(($semRef.Id) -join ', ')" }
        $criterios = Get-DodCriteria $LoopId
        $desconhecidas = @($items.Refs | Where-Object { -not $criterios.Contains($_) } | Select-Object -Unique)
        if ($desconhecidas) { throw "Referências inexistentes na DoD: $($desconhecidas -join ', ')" }

        $globs = Get-PlanWriteScope $plan
        $state.escopo_escrita_atual = $globs
        $detalhe = "$detalhe; itens=$($items.Count); escopo=$($globs -join ', ')"
    }
    'CHECK' {
        $plan = Join-Path $iterDir "planejamento-iteracao-$nn.md"
        $items = Get-PlanItems $plan
        $pendentes = @($items | Where-Object { $_.Marca -eq ' ' })
        if ($pendentes) {
            if (-not $PermitirPendentes) { throw "Itens do plano não executados: $(($pendentes.Id) -join ', '). Marque como [x], [~] ou [!]." }
            $alertas.Add("Itens pendentes ao final da implementação: $(($pendentes.Id) -join ', ')")
        }
        $state.escopo_escrita_atual = @()
        $stats = ($items | Group-Object Marca | ForEach-Object { "$($_.Name.Replace(' ', 'pendente'))=$($_.Count)" }) -join '; '
        $detalhe = "$detalhe; $stats"
    }
    'VERIFY' {
        $chk = Join-Path $iterDir "checagem-iteracao-$nn.md"
        $linha = Select-String -Path $chk -Pattern '^\s*\**Status geral\**\s*:\s*\**\s*(VERDE|VERMELHO)\b'
        if (-not $linha) { throw "Checagem sem 'Status geral: VERDE|VERMELHO' em $chk." }
        $detalhe = "$detalhe; check=$($linha.Matches[0].Groups[1].Value)"
    }
}

$state.fase = $Fase
foreach ($a in $alertas) { $state.alertas += "[it $n] $a" }
Save-LoopState -LoopId $LoopId -State $state
foreach ($a in $alertas) { Write-LoopEvent -LoopId $LoopId -Acao 'ALERTA' -Resultado 'ALERTA' -Detalhe $a }
Write-LoopEvent -LoopId $LoopId -Acao 'FASE_ALTERADA' -Alvo $Fase -Detalhe $detalhe

Write-LoopResult @{
    loop_id           = $LoopId
    fase              = $Fase
    iteracao          = $n
    aguardando_humano = [bool]$state.aguardando_humano
    escopo_escrita    = @($state.escopo_escrita_atual)
    alertas           = @($alertas)
}
