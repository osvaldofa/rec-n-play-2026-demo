#Requires -Version 7.0
<#
.SYNOPSIS
    Registra a aprovação humana da DoD (GATE_DOD -> PLAN), congela spec/DoD e abre a iteração 1.
.DESCRIPTION
    - Lê a tabela "Comandos técnicos" da spec refinada e congela os comandos no estado.
    - Calcula o hash SHA-256 de 00/01/02 (usado pelo verificador e pelos guard rails).
    - Cria a pasta iteracao-01 com os templates.
.EXAMPLE
    ./Approve-LoopDod.ps1 -AprovadoPor "osvaldofa"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AprovadoPor,
    [string]$LoopId,
    [string]$Observacao = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LoopCommon.psm1') -Force

$LoopId = Resolve-LoopId $LoopId
$state = Read-LoopState $LoopId
$dir = Get-LoopDir $LoopId
if ($state.status -ne 'EM_ANDAMENTO' -or $state.fase -ne 'GATE_DOD') {
    throw "A DoD só pode ser aprovada na fase GATE_DOD (atual: $($state.status)/$($state.fase))."
}

$criterios = Get-DodCriteria $LoopId

$spec = Join-Path $dir '01-spec-refinada.md'
$validos = @('restore', 'build', 'lint', 'test', 'coverage', 'static_analysis', 'dependency_audit', 'smoke')
foreach ($t in (Get-MarkdownTables $spec)) {
    if ('etapa' -notin $t.Headers -or 'comando' -notin $t.Headers) { continue }
    foreach ($r in $t.Rows) {
        $etapa = (ConvertTo-NormalizedKey ($r['etapa'] -replace '`', ''))
        $cmd = ($r['comando'] -replace '^`+|`+$', '').Trim()
        if ($etapa -in $validos -and $cmd -and $cmd -notmatch '^(<.*>|-|n/?a)$') { $state.comandos[$etapa] = $cmd }
    }
}
$alertas = [System.Collections.Generic.List[string]]::new()
foreach ($obrig in 'build', 'test', 'coverage', 'smoke') {
    if ([string]::IsNullOrWhiteSpace($state.comandos[$obrig])) { throw "Comando técnico obrigatório não definido na spec refinada (tabela 'Comandos técnicos'): $obrig." }
}
if ($state.comandos.coverage -notmatch '100') {
    $alertas.Add('O comando de cobertura não contém o limiar 100 explícito; garanta que a configuração da ferramenta falhe abaixo de 100% (PT-04).')
}

$hashes = [ordered]@{}
foreach ($f in '00-spec-original.md', '01-spec-refinada.md', '02-definicao-de-pronto.md') { $hashes[$f] = Get-FileSha256 (Join-Path $dir $f) }

$state.dod.versao = [int]$state.dod.versao + 1
$state.dod.congelada = $true
$state.dod.aprovada_por = $AprovadoPor
$state.dod.aprovada_em = Get-LoopTimestamp
$state.dod.hash_sha256 = $hashes['02-definicao-de-pronto.md']
$state.dod.hashes = $hashes
foreach ($a in $alertas) { $state.alertas += "[DoD] $a" }
Save-LoopState -LoopId $LoopId -State $state

Write-LoopEvent -LoopId $LoopId -Acao 'DOD_APROVADA' -Agente 'humano' -Alvo '02-definicao-de-pronto.md' -Detalhe ("v{0}; por {1}; criterios={2}; hash={3}; {4}" -f $state.dod.versao, $AprovadoPor, $criterios.Count, $state.dod.hash_sha256.Substring(0, 12), $Observacao)
foreach ($a in $alertas) { Write-LoopEvent -LoopId $LoopId -Acao 'ALERTA' -Resultado 'ALERTA' -Detalhe $a }

$state = Read-LoopState $LoopId
$n = New-LoopIteration -LoopId $LoopId -State $state

Write-LoopResult @{
    loop_id    = $LoopId
    fase       = 'PLAN'
    iteracao   = $n
    dod_versao = $state.dod.versao
    criterios  = $criterios.Count
    gates      = @($criterios.Values | Where-Object { $_.gate }).Count
    comandos   = $state.comandos
    alertas    = @($alertas)
}
