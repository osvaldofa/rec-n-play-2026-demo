#Requires -Version 7.0
<#
.SYNOPSIS
    Cria a estrutura de um novo loop (fase INTAKE) e o deixa pronto para REFINE.
.DESCRIPTION
    Com -LoopAnterior (D-17), cria a nova versão de um loop encerrado (ABORTED ou DONE) cujo contrato
    precisa mudar: a spec de entrada passa a ser a spec refinada do loop anterior acrescida da
    decisão humana sobre a regra (SpecText/SpecPath). O novo loop passa por novo REFINE e novo GATE_DOD.
.EXAMPLE
    ./Initialize-Loop.ps1 -Nome "calculo-desconto" -SpecPath specs/calculo-desconto.md
.EXAMPLE
    ./Initialize-Loop.ps1 -Nome "calculo-desconto" -SpecText "Criar uma API que..." -MaxIteracoes 4
.EXAMPLE
    ./Initialize-Loop.ps1 -Nome "calculo-desconto-v2" -LoopAnterior loop-calculo-desconto -SpecText "RN-02: arredondar para baixo, 2 casas"
#>
[CmdletBinding(DefaultParameterSetName = 'Arquivo')]
param(
    [Parameter(Mandatory)][string]$Nome,
    [Parameter(Mandatory, ParameterSetName = 'Arquivo')][string]$SpecPath,
    [Parameter(Mandatory, ParameterSetName = 'Texto')][string]$SpecText,
    [string]$LoopAnterior,
    [ValidateRange(1, 20)][int]$MaxIteracoes,
    [ValidateRange(0.5, 1.0)][double]$Limiar,
    [switch]$SubstituirAtivo
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

$slug = ($Nome.ToLowerInvariant().Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{Mn}', '' -replace '[^a-z0-9]+', '-').Trim('-')
if (-not $slug) { throw 'Nome inválido para o loop.' }
$loopId = if ($slug.StartsWith('loop-')) { $slug } else { "loop-$slug" }

$active = Get-ActiveLoopId
if ($active -and $active -ne $loopId -and -not $SubstituirAtivo) {
    $st = Read-LoopState $active
    if ($st.status -eq 'EM_ANDAMENTO') {
        throw "Já existe um loop ativo em andamento: '$active' (fase $($st.fase)). Encerre-o ou use -SubstituirAtivo."
    }
}

$dir = Get-LoopDir $loopId
if (Test-Path $dir) { throw "O loop '$loopId' já existe em $dir. Use /loop-resume para retomá-lo." }

if ($PSCmdlet.ParameterSetName -eq 'Arquivo') {
    $full = if ([System.IO.Path]::IsPathRooted($SpecPath)) { $SpecPath } else { Join-Path (Get-LoopRepoRoot) $SpecPath }
    if (-not (Test-Path $full)) { throw "Spec não encontrada: $full" }
    $specContent = Get-Content $full -Raw -Encoding utf8
    $origem = ConvertTo-LoopRelativePath $full
} else {
    $specContent = $SpecText
    $origem = 'texto informado no prompt'
}
if ([string]::IsNullOrWhiteSpace($specContent)) { throw 'A especificação está vazia.' }

$anterior = $null
if ($LoopAnterior) {
    $LoopAnterior = Resolve-LoopId $LoopAnterior
    if ($LoopAnterior -eq $loopId) { throw 'O novo loop precisa de um nome diferente do loop anterior.' }
    $anterior = Read-LoopState $LoopAnterior
    if ($anterior.status -notin @('ABORTED', 'DONE')) { throw "O loop anterior '$LoopAnterior' precisa estar encerrado (ABORTED ou DONE); atual: $($anterior.status). Aborte-o antes com Resolve-LoopEscalation.ps1 -Decisao Abortar." }
    $specAnterior = Join-Path (Get-LoopDir $LoopAnterior) '01-spec-refinada.md'
    $base = Get-Content $specAnterior -Raw -Encoding utf8
    $motivoAnt = if ($anterior.Contains('parada') -and $anterior.parada) { $anterior.parada.motivo } else { $anterior.motivo_encerramento }
    $specContent = @"
## Contexto da nova versão

Este loop substitui ``$LoopAnterior`` (status $($anterior.status), motivo $motivoAnt, DoD v$($anterior.dod.versao)).
A base é a spec refinada aprovada do loop anterior; as **alterações decididas** abaixo prevalecem sobre ela.
O código já produzido pelo loop anterior permanece no repositório e é o ponto de partida do planejamento.

## Alterações decididas

$specContent

## Spec refinada do loop anterior (base)

$base
"@
    $origem = "loops/$LoopAnterior/01-spec-refinada.md + alterações decididas ($origem)"
}

$cfg = Get-LoopConfig
$limites = [ordered]@{}
foreach ($k in $cfg.limites.Keys) { $limites[$k] = $cfg.limites[$k] }
if ($PSBoundParameters.ContainsKey('MaxIteracoes')) { $limites.max_iteracoes = $MaxIteracoes }
if ($PSBoundParameters.ContainsKey('Limiar')) { $limites.limiar_aderencia = $Limiar }

$comandos = [ordered]@{}
foreach ($k in $cfg.comandos_padrao.Keys) { $comandos[$k] = $cfg.comandos_padrao[$k] }

New-Item -ItemType Directory -Path $dir -Force | Out-Null
$utf8 = [System.Text.UTF8Encoding]::new($false)
$agora = Get-LoopTimestamp

$header = @"
# Spec original — $loopId

> Origem: $origem · Registrada em: $agora
> Documento imutável. Refinamentos vão para ``01-spec-refinada.md``.

---

"@
[System.IO.File]::WriteAllText((Join-Path $dir '00-spec-original.md'), $header + $specContent, $utf8)

$tokens = @{ LOOP_ID = $loopId; LIMIAR = ('{0:0.00}' -f $limites.limiar_aderencia).Replace('.', ',') }
Copy-LoopTemplate -Template 'spec-refinada.md' -Destination (Join-Path $dir '01-spec-refinada.md') -Tokens $tokens
Copy-LoopTemplate -Template 'definicao-de-pronto.md' -Destination (Join-Path $dir '02-definicao-de-pronto.md') -Tokens $tokens

$state = [ordered]@{
    versao_protocolo     = 1
    loop_id              = $loopId
    status               = 'EM_ANDAMENTO'
    fase                 = 'INTAKE'
    iteracao_atual       = 0
    aguardando_humano    = $false
    criado_em            = $agora
    atualizado_em        = $agora
    spec_origem          = $origem
    limites              = $limites
    comandos             = $comandos
    dod                  = [ordered]@{
        versao        = 0
        congelada     = $false
        aprovada_por  = $null
        aprovada_em   = $null
        hash_sha256   = $null
        hashes        = [ordered]@{}
    }
    escopo_escrita_atual = @()
    historico            = @()
    falhas_por_criterio  = [ordered]@{}
    ponto_retomada       = 0
    parada               = $null
    paradas              = @()
    loop_anterior        = $LoopAnterior
    substituido_por      = $null
    alertas              = @()
    motivo_encerramento  = $null
}
[System.IO.File]::WriteAllText((Join-Path $dir 'log.jsonl'), '', $utf8)
Save-LoopState -LoopId $loopId -State $state
Set-ActiveLoopId $loopId

Write-LoopEvent -LoopId $loopId -Acao 'LOOP_INICIADO' -Alvo $origem -Fase 'INTAKE' -Iteracao 0 -Detalhe ("max_iteracoes={0}; limiar={1}{2}" -f $limites.max_iteracoes, $limites.limiar_aderencia, $(if ($anterior) { "; substitui=$LoopAnterior" } else { '' }))

if ($anterior) {
    $anterior.substituido_por = $loopId
    Save-LoopState -LoopId $LoopAnterior -State $anterior
    Write-LoopEvent -LoopId $LoopAnterior -Acao 'LOOP_SUBSTITUIDO' -Agente 'protocolo' -Alvo $loopId -Detalhe "Nova versão do contrato (D-17) iniciada em $loopId"
}

$state = Read-LoopState $loopId
$state.fase = 'REFINE'
Save-LoopState -LoopId $loopId -State $state
Write-LoopEvent -LoopId $loopId -Acao 'FASE_ALTERADA' -Alvo 'REFINE' -Detalhe 'INTAKE -> REFINE'

Write-LoopResult @{
    loop_id    = $loopId
    diretorio  = ConvertTo-LoopRelativePath $dir
    fase       = 'REFINE'
    artefatos  = @(
        "loops/$loopId/00-spec-original.md",
        "loops/$loopId/01-spec-refinada.md",
        "loops/$loopId/02-definicao-de-pronto.md",
        "loops/$loopId/loop-state.json",
        "loops/$loopId/log.jsonl"
    )
    limites    = $limites
    loop_anterior = $LoopAnterior
}
