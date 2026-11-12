#Requires -Version 7.0
# Funções compartilhadas pelo protocolo do loop e pelos hooks de guard rail.

Set-StrictMode -Version Latest

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)

$script:Fases = @('INTAKE', 'REFINE', 'GATE_DOD', 'PLAN', 'IMPLEMENT', 'CHECK', 'VERIFY', 'DECIDE')
$script:StatusTerminais = @('DONE', 'ABORTED')
# D-17: paradas que envolvem o contrato (regra de negócio, critério ou teste congelado) não admitem retomada no mesmo loop.
$script:MotivosContrato = @('AMBIGUIDADE_REGRA', 'CONTESTACAO_CRITERIO', 'CONTESTACAO_TESTE')

function Get-LoopRepoRoot { $script:RepoRoot }

function Get-LoopTimestamp { (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') }

function Get-LoopConfig {
    $path = Join-Path $script:RepoRoot '.github\loop-config.json'
    if (-not (Test-Path $path)) { throw "Configuração não encontrada: $path" }
    Get-Content $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
}

function Get-LoopsRoot { Join-Path $script:RepoRoot 'loops' }

function Get-ActiveLoopId {
    $file = Join-Path (Get-LoopsRoot) '.active'
    if (-not (Test-Path $file)) { return $null }
    $id = (Get-Content $file -Raw -Encoding utf8).Trim()
    if ([string]::IsNullOrWhiteSpace($id)) { return $null }
    if (-not (Test-Path (Join-Path (Get-LoopsRoot) "$id\loop-state.json"))) { return $null }
    $id
}

function Set-ActiveLoopId {
    param([AllowNull()][string]$LoopId)
    $file = Join-Path (Get-LoopsRoot) '.active'
    if ([string]::IsNullOrWhiteSpace($LoopId)) {
        if (Test-Path $file) { Remove-Item $file -Force }
        return
    }
    [System.IO.File]::WriteAllText($file, $LoopId, $script:Utf8)
}

function Resolve-LoopId {
    param([string]$LoopId)
    if (-not [string]::IsNullOrWhiteSpace($LoopId)) {
        if ($LoopId -notmatch '^loop-') { $LoopId = "loop-$LoopId" }
        return $LoopId
    }
    $active = Get-ActiveLoopId
    if (-not $active) { throw 'Nenhum loop informado e nenhum loop ativo (loops/.active).' }
    $active
}

function Get-LoopDir {
    param([Parameter(Mandatory)][string]$LoopId)
    Join-Path (Get-LoopsRoot) $LoopId
}

function Get-IterationName {
    param([Parameter(Mandatory)][int]$Iteracao)
    'iteracao-{0:D2}' -f $Iteracao
}

function Get-IterationDir {
    param([Parameter(Mandatory)][string]$LoopId, [Parameter(Mandatory)][int]$Iteracao)
    Join-Path (Get-LoopDir $LoopId) (Get-IterationName $Iteracao)
}

function Read-LoopState {
    param([Parameter(Mandatory)][string]$LoopId)
    $path = Join-Path (Get-LoopDir $LoopId) 'loop-state.json'
    if (-not (Test-Path $path)) { throw "Estado não encontrado para o loop '$LoopId': $path" }
    Get-Content $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
}

function Save-LoopState {
    param([Parameter(Mandatory)][string]$LoopId, [Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $State.atualizado_em = Get-LoopTimestamp
    $path = Join-Path (Get-LoopDir $LoopId) 'loop-state.json'
    $tmp = "$path.tmp"
    [System.IO.File]::WriteAllText($tmp, ($State | ConvertTo-Json -Depth 20), $script:Utf8)
    Move-Item -Path $tmp -Destination $path -Force
}

function Write-LoopEvent {
    param(
        [Parameter(Mandatory)][string]$LoopId,
        [Parameter(Mandatory)][string]$Acao,
        [string]$Agente = 'protocolo',
        [string]$Alvo = '',
        [ValidateSet('OK', 'FALHA', 'BLOQUEADO', 'CONFIRMACAO', 'ALERTA')][string]$Resultado = 'OK',
        [Nullable[long]]$DuracaoMs = $null,
        [string]$Detalhe = '',
        [string]$Fase,
        [Nullable[int]]$Iteracao = $null
    )
    if (-not $Fase -or $null -eq $Iteracao) {
        try {
            $st = Read-LoopState $LoopId
            if (-not $Fase) { $Fase = $st.fase }
            if ($null -eq $Iteracao) { $Iteracao = [int]$st.iteracao_atual }
        } catch {
            if (-not $Fase) { $Fase = 'DESCONHECIDA' }
            if ($null -eq $Iteracao) { $Iteracao = 0 }
        }
    }
    $evento = [ordered]@{
        ts         = Get-LoopTimestamp
        loop       = $LoopId
        iteracao   = $Iteracao
        fase       = $Fase
        agente     = $Agente
        acao       = $Acao
        alvo       = $Alvo
        resultado  = $Resultado
        duracao_ms = $DuracaoMs
        detalhe    = $Detalhe
    }
    $line = ($evento | ConvertTo-Json -Compress -Depth 5) + [Environment]::NewLine
    $path = Join-Path (Get-LoopDir $LoopId) 'log.jsonl'
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try {
                $bytes = $script:Utf8.GetBytes($line)
                $fs.Write($bytes, 0, $bytes.Length)
            } finally { $fs.Dispose() }
            return
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (25 * ($i + 1))
        }
    }
    throw "Não foi possível gravar evento em $path"
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-LoopRelativePath {
    param([Parameter(Mandatory)][string]$Path, [string]$BaseDir = $script:RepoRoot)
    $p = $Path.Trim().Trim('"').Trim("'")
    if ($p -match '^file:///?') { $p = [System.Uri]::UnescapeDataString(($p -replace '^file:///?', '')) }
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $BaseDir $p }
    $full = [System.IO.Path]::GetFullPath($p)
    $root = [System.IO.Path]::GetFullPath($script:RepoRoot).TrimEnd('\', '/')
    if ($full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($full.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/')
    }
    $full -replace '\\', '/'
}

function ConvertFrom-LoopGlob {
    param([Parameter(Mandatory)][string]$Glob)
    $g = ($Glob.Trim() -replace '\\', '/') -replace '^(\./)+', ''
    $sb = [System.Text.StringBuilder]::new('^')
    $i = 0
    while ($i -lt $g.Length) {
        $c = $g[$i]
        if ($c -eq '*') {
            if ($i + 1 -lt $g.Length -and $g[$i + 1] -eq '*') {
                if ($i + 2 -lt $g.Length -and $g[$i + 2] -eq '/') { [void]$sb.Append('(?:.*/)?'); $i += 3; continue }
                [void]$sb.Append('.*'); $i += 2; continue
            }
            [void]$sb.Append('[^/]*')
        } elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
        } else {
            [void]$sb.Append([regex]::Escape([string]$c))
        }
        $i++
    }
    [void]$sb.Append('$')
    $sb.ToString()
}

function Test-LoopGlob {
    param([Parameter(Mandatory)][string]$RelativePath, [string[]]$Globs)
    if (-not $Globs) { return $false }
    $rp = $RelativePath -replace '\\', '/'
    foreach ($g in $Globs) {
        if ([string]::IsNullOrWhiteSpace($g)) { continue }
        if ($rp -match ('(?i)' + (ConvertFrom-LoopGlob $g))) { return $true }
    }
    $false
}

function ConvertTo-NormalizedKey {
    param([string]$Text)
    $d = $Text.Trim().ToLowerInvariant().Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $d.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    ($sb.ToString() -replace '[^a-z0-9]+', '_').Trim('_')
}

function Split-MarkdownRow {
    param([string]$Line)
    $t = $Line.Trim()
    if ($t.StartsWith('|')) { $t = $t.Substring(1) }
    if ($t.EndsWith('|')) { $t = $t.Substring(0, $t.Length - 1) }
    @($t -split '(?<!\\)\|' | ForEach-Object { $_.Trim() })
}

function Get-MarkdownTables {
    param([Parameter(Mandatory)][string]$Path)
    $lines = Get-Content $Path -Encoding utf8
    $tables = [System.Collections.Generic.List[object]]::new()
    $i = 0
    $inFence = $false
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line.TrimStart().StartsWith('```')) { $inFence = -not $inFence; $i++; continue }
        if (-not $inFence -and $line.Trim().StartsWith('|') -and ($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s*\|?\s*:?-{3,}') {
            $headers = Split-MarkdownRow $line | ForEach-Object { ConvertTo-NormalizedKey $_ }
            $rows = [System.Collections.Generic.List[hashtable]]::new()
            $i += 2
            while ($i -lt $lines.Count -and $lines[$i].Trim().StartsWith('|')) {
                $cells = Split-MarkdownRow $lines[$i]
                $row = @{}
                for ($c = 0; $c -lt $headers.Count; $c++) { $row[$headers[$c]] = if ($c -lt $cells.Count) { $cells[$c] } else { '' } }
                $rows.Add($row)
                $i++
            }
            $tables.Add([pscustomobject]@{ Headers = @($headers); Rows = $rows })
            continue
        }
        $i++
    }
    , $tables
}

function Get-MarkdownSection {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$HeadingPattern)
    $lines = Get-Content $Path -Encoding utf8
    $out = [System.Collections.Generic.List[string]]::new()
    $capturing = $false
    $level = 0
    foreach ($l in $lines) {
        if ($l -match '^(#{1,6})\s+(.*)$') {
            $lvl = $Matches[1].Length
            if ($capturing -and $lvl -le $level) { break }
            if (-not $capturing -and $Matches[2] -match $HeadingPattern) { $capturing = $true; $level = $lvl; continue }
        }
        if ($capturing) { $out.Add($l) }
    }
    , $out
}

function ConvertTo-LoopNumber {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = ($Text -replace '\*', '').Trim().Replace(',', '.')
    $n = 0.0
    if ([double]::TryParse($t, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }
    $null
}

function Test-LoopYes {
    param([string]$Text)
    (ConvertTo-NormalizedKey $Text) -in @('sim', 'yes', 's', 'y', 'true', 'gate', 'x')
}

function Copy-LoopTemplate {
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$Destination,
        [hashtable]$Tokens = @{}
    )
    $src = Join-Path $script:RepoRoot ".github\skills\loop-protocol\templates\$Template"
    if (-not (Test-Path $src)) { throw "Template não encontrado: $src" }
    $content = Get-Content $src -Raw -Encoding utf8
    foreach ($k in $Tokens.Keys) { $content = $content.Replace("{{$k}}", [string]$Tokens[$k]) }
    [System.IO.File]::WriteAllText($Destination, $content, $script:Utf8)
}

function Get-LoopNextAction {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $s = '.github/skills/loop-protocol/scripts'
    switch ($State.status) {
        'DONE' { return 'Loop concluído. Nenhuma ação pendente.' }
        'ABORTED' { return 'Loop abortado. Nenhuma ação pendente.' }
        'ESCALATED' {
            $p = if ($State.Contains('parada') -and $State.parada) { "parado em $($State.parada.fase) da iteração $($State.parada.iteracao) ($($State.parada.motivo))" } else { "parado ($($State.motivo_encerramento))" }
            if ($State.motivo_encerramento -in $script:MotivosContrato) {
                return "AGUARDAR HUMANO: loop $p. Motivo de contrato (D-17): não há retomada no mesmo loop. Abortar ($s/Resolve-LoopEscalation.ps1 -Decisao Abortar -AutorizadoPor <usuario>) e iniciar um novo loop a partir da spec refinada revisada ($s/Initialize-Loop.ps1 -Nome <nome-v2> -LoopAnterior $($State.loop_id) -SpecText '<decisão sobre a regra>')."
            }
            return "AGUARDAR HUMANO: loop $p. Retomar do ponto de parada ($s/Resolve-LoopEscalation.ps1 -Decisao Continuar -AutorizadoPor <usuario> [-IteracoesExtras N] [-Motivo '<orientação técnica>']) ou abortar (-Decisao Abortar)."
        }
    }
    switch ($State.fase) {
        'INTAKE' { "Executar $s/Initialize-Loop.ps1." }
        'REFINE' { "Acionar loop-refiner para preencher 01-spec-refinada.md e 02-definicao-de-pronto.md; depois $s/Set-LoopPhase.ps1 -Fase GATE_DOD." }
        'GATE_DOD' { "AGUARDAR HUMANO: aprovar a DoD ($s/Approve-LoopDod.ps1 -AprovadoPor <usuario>) ou solicitar ajustes ($s/Set-LoopPhase.ps1 -Fase REFINE -Motivo '<ajustes>')." }
        'PLAN' { "Acionar loop-planner, persistir planejamento-iteracao-NN.md e executar $s/Set-LoopPhase.ps1 -Fase IMPLEMENT." }
        'IMPLEMENT' { "Acionar loop-implementer para executar todo o checklist; depois $s/Set-LoopPhase.ps1 -Fase CHECK." }
        'CHECK' { "Acionar loop-checker, persistir checagem-iteracao-NN.md e executar $s/Set-LoopPhase.ps1 -Fase VERIFY." }
        'VERIFY' { "Acionar loop-verifier, persistir verificacao-iteracao-NN.md e executar $s/Invoke-LoopDecision.ps1." }
        'DECIDE' { "Executar $s/Invoke-LoopDecision.ps1." }
        default { 'Fase desconhecida; verificar loop-state.json.' }
    }
}

function Get-PlanWriteScope {
    param([Parameter(Mandatory)][string]$Path)
    $secao = Get-MarkdownSection -Path $Path -HeadingPattern '(?i)^escopo de escrita'
    $globs = @($secao | Where-Object { $_ -match '^\s*[-*]\s+`?([^`]+?)`?\s*$' } | ForEach-Object { ($_ -replace '^\s*[-*]\s+', '').Trim().Trim('`').Trim() } | Where-Object { $_ -and $_ -notmatch '^<' })
    if ($globs.Count -eq 0) { throw "O plano não declara a seção 'Escopo de escrita' com ao menos um glob." }
    foreach ($g in $globs) {
        $norm = ($g -replace '\\', '/') -replace '^(\./)+', ''
        if ($norm -in @('*', '**', '**/*', '/**')) { throw "Escopo de escrita amplo demais: '$g'." }
        if ($norm -match '^(loops|\.github)(/|$)') { throw "Escopo de escrita não pode incluir '$g' (área do processo/harness)." }
    }
    , $globs
}

function Write-LoopFinalReport {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $hist = @($State.historico)
    $linhas = foreach ($h in $hist) {
        '| {0} | {1} | {2} | {3} | {4} | {5} |' -f $h.iteracao, $h.check, ('{0:0.00}' -f [double]$h.indice).Replace('.', ','), (@($h.gates_pendentes) -join ', '), $h.decisao, ($h.motivo ?? '')
    }
    $ultimo = if ($hist.Count) { $hist[-1] } else { $null }
    $motivo = [string]$State.motivo_encerramento
    if ($State.Contains('parada') -and $State.parada) { $motivo = "$motivo — parado em $($State.parada.fase) (iteração $($State.parada.iteracao)): $($State.parada.detalhe)" }
    $tokens = @{
        LOOP_ID         = $State.loop_id
        STATUS          = $State.status
        MOTIVO          = $motivo
        ITERACOES       = $State.iteracao_atual
        INDICE_FINAL    = if ($ultimo) { ('{0:0.00}' -f [double]$ultimo.indice).Replace('.', ',') } else { 'n/a' }
        LIMIAR          = ('{0:0.00}' -f [double]$State.limites.limiar_aderencia).Replace('.', ',')
        CURVA           = if ($linhas) { $linhas -join "`n" } else { '| - | - | - | - | - | - |' }
        GATES_PENDENTES = if ($ultimo -and @($ultimo.gates_pendentes).Count) { (@($ultimo.gates_pendentes) | ForEach-Object { "- $_" }) -join "`n" } elseif ($ultimo) { '- Nenhum' } else { '- Nenhuma iteração avaliada' }
        GERADO_EM       = Get-LoopTimestamp
    }
    Copy-LoopTemplate -Template 'resultado-final.md' -Destination (Join-Path (Get-LoopDir $State.loop_id) 'resultado-final.md') -Tokens $tokens
}

function Invoke-LoopStop {
    # Condição de parada: nenhum humano avalia a iteração; o loop para e registra o ponto exato para retomada.
    param(
        [Parameter(Mandatory)][string]$LoopId,
        [Parameter(Mandatory)][string]$Motivo,
        [string]$Detalhe = '',
        [string]$Agente = 'protocolo',
        [string]$Fase
    )
    $State = Read-LoopState $LoopId
    if ($State.status -ne 'EM_ANDAMENTO') { throw "Só é possível parar um loop em andamento (atual: $($State.status))." }
    $faseParada = if ($Fase) { $Fase } else { $State.fase }
    $State.status = 'ESCALATED'
    $State.motivo_encerramento = $Motivo
    $State.aguardando_humano = $true
    $State.escopo_escrita_atual = @()
    $State.parada = [ordered]@{
        fase      = $faseParada
        iteracao  = [int]$State.iteracao_atual
        motivo    = $Motivo
        detalhe   = $Detalhe
        agente    = $Agente
        em        = Get-LoopTimestamp
    }
    Save-LoopState -LoopId $LoopId -State $State
    Write-LoopFinalReport $State
    Write-LoopEvent -LoopId $LoopId -Acao 'LOOP_PARADO' -Agente $Agente -Alvo $faseParada -Resultado 'ALERTA' -Fase $faseParada -Detalhe "motivo=$Motivo; $Detalhe"
    $State
}

function Get-LoopContractDivergence {
    # Arquivos congelados no GATE_DOD cujo hash atual difere do aprovado.
    param([Parameter(Mandatory)][string]$LoopId, [Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $div = [System.Collections.Generic.List[string]]::new()
    if (-not $State.dod.congelada -or -not $State.dod.Contains('hashes') -or -not $State.dod.hashes) { return , $div }
    $dir = Get-LoopDir $LoopId
    foreach ($f in $State.dod.hashes.Keys) {
        $p = Join-Path $dir $f
        if (-not (Test-Path $p) -or (Get-FileSha256 $p) -ne $State.dod.hashes[$f]) { $div.Add($f) }
    }
    , $div
}

function Write-LoopResult {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data)
    $Data | ConvertTo-Json -Depth 10
}

function Get-DodCriteria {
    param([Parameter(Mandatory)][string]$LoopId)
    $path = Join-Path (Get-LoopDir $LoopId) '02-definicao-de-pronto.md'
    if (-not (Test-Path $path)) { throw "DoD não encontrada: $path" }
    $criterios = [ordered]@{}
    foreach ($t in (Get-MarkdownTables $path)) {
        if ('id' -notin $t.Headers -or 'peso' -notin $t.Headers -or 'gate' -notin $t.Headers) { continue }
        foreach ($r in $t.Rows) {
            $id = ($r['id'] -replace '\*', '').Trim()
            if ($id -notmatch '^(DOD|PT)-\d{2,}$') { continue }
            $peso = ConvertTo-LoopNumber $r['peso']
            if ($null -eq $peso -or $peso -lt 1 -or $peso -gt 3) { throw "Critério $id com peso inválido ('$($r['peso'])'). Use 1, 2 ou 3." }
            if ($criterios.Contains($id)) { throw "Critério duplicado na DoD: $id" }
            $descricao = foreach ($k in 'descricao_verificavel', 'descricao', 'padrao', 'criterio') { if ($r.ContainsKey($k) -and $r[$k]) { $r[$k]; break } }
            $criterios[$id] = [ordered]@{ id = $id; peso = [double]$peso; gate = (Test-LoopYes $r['gate']); descricao = [string]$descricao }
        }
    }
    if ($criterios.Count -eq 0) { throw 'A DoD não contém critérios (tabelas com colunas ID, Peso e Gate).' }
    $criterios
}

function Get-PlanItems {
    param([Parameter(Mandatory)][string]$Path)
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($l in (Get-Content $Path -Encoding utf8)) {
        if ($l -match '^\s*[-*]\s*\[(?<m>[ xX~!])\]\s*(?<id>P-\d{2}-\d{2,})\b(?<txt>.*)$') {
            $refs = @([regex]::Matches($Matches.txt, '\b(?:DOD|PT)-\d{2,}\b') | ForEach-Object Value | Select-Object -Unique)
            $items.Add([pscustomobject]@{ Marca = $Matches.m.ToLowerInvariant(); Id = $Matches.id; Texto = $Matches.txt.Trim(); Refs = $refs })
        }
    }
    , $items
}

function New-LoopIteration {
    param([Parameter(Mandatory)][string]$LoopId, [Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $n = [int]$State.iteracao_atual + 1
    if ($n -gt [int]$State.limites.max_iteracoes) { throw "Limite de iterações atingido ($($State.limites.max_iteracoes)). Não é possível abrir a iteração $n." }
    $dir = Get-IterationDir $LoopId $n
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $nn = '{0:D2}' -f $n
    $tokens = @{ LOOP_ID = $LoopId; ITERACAO = $nn }
    foreach ($tpl in 'planejamento-iteracao', 'checagem-iteracao', 'verificacao-iteracao', 'log-iteracao') {
        $dest = Join-Path $dir "$tpl-$nn.md"
        if (-not (Test-Path $dest)) { Copy-LoopTemplate -Template "$tpl.md" -Destination $dest -Tokens $tokens }
    }
    $anterior = $State.fase
    $State.iteracao_atual = $n
    $State.fase = 'PLAN'
    $State.aguardando_humano = $false
    $State.escopo_escrita_atual = @()
    Save-LoopState -LoopId $LoopId -State $State
    Write-LoopEvent -LoopId $LoopId -Acao 'ITERACAO_INICIADA' -Alvo (Get-IterationName $n) -Detalhe "$anterior -> PLAN"
    $n
}

Export-ModuleMember -Function * -Variable Fases, StatusTerminais, MotivosContrato
