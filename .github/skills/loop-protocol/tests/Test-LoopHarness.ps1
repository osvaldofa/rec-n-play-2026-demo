#Requires -Version 7.0
<#
.SYNOPSIS
    Auto-teste do harness do loop: executa o ciclo de vida completo e os hooks em uma cópia isolada.
.DESCRIPTION
    Copia .github/ para uma pasta temporária e valida:
      - transições de fase e validações (placeholders, plano, escopo, pendências)
      - aprovação/congelamento da DoD e comandos técnicos
      - cálculo do índice e algoritmo de decisão (CONTINUAR, DONE, LIMITE, retomada, aborto)
      - guard rails (preToolUse), observabilidade (eventos) e continuidade (agentStop)
.EXAMPLE
    pwsh -File .github/skills/loop-protocol/tests/Test-LoopHarness.ps1
.EXAMPLE
    pwsh -File .github/skills/loop-protocol/tests/Test-LoopHarness.ps1 -Manter
#>
param([switch]$Manter)

$ErrorActionPreference = 'Stop'
$origem = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$raiz = Join-Path ([System.IO.Path]::GetTempPath()) ("loop-harness-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $raiz | Out-Null
Copy-Item (Join-Path $origem '.github') -Destination $raiz -Recurse
New-Item -ItemType Directory -Path (Join-Path $raiz 'loops'), (Join-Path $raiz 'src\feature'), (Join-Path $raiz 'tests\feature') -Force | Out-Null

$scripts = Join-Path $raiz '.github\skills\loop-protocol\scripts'
$hooks = Join-Path $raiz '.github\hooks\scripts'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$script:ok = 0; $script:falhas = [System.Collections.Generic.List[string]]::new()

function Assert([bool]$Cond, [string]$Nome) {
    if ($Cond) { $script:ok++; Write-Host "  [OK]   $Nome" -ForegroundColor Green }
    else { $script:falhas.Add($Nome); Write-Host "  [FALHA] $Nome" -ForegroundColor Red }
}
function Run([string]$Nome, [hashtable]$Params = @{}) {
    $r = & (Join-Path $scripts $Nome) @Params
    if ($r -is [array]) { $r = $r -join "`n" }
    try { $r | ConvertFrom-Json -AsHashtable } catch { $r }
}
function Throws([string]$Nome, [hashtable]$Params, [string]$Padrao, [string]$Descricao) {
    try { & (Join-Path $scripts $Nome) @Params | Out-Null; Assert $false "$Descricao (esperava erro)" }
    catch { Assert ($_.Exception.Message -match $Padrao) "$Descricao [$($_.Exception.Message)]" }
}
function Hook([string]$Script, [hashtable]$Payload, [string[]]$Extra = @()) {
    $json = $Payload | ConvertTo-Json -Depth 10 -Compress
    $out = $json | pwsh -NoProfile -NonInteractive -File (Join-Path $hooks $Script) @Extra
    $txt = ($out -join "`n").Trim()
    if (-not $txt) { return @{} }
    $txt | ConvertFrom-Json -AsHashtable
}
function Guard([string]$Tool, [hashtable]$ToolArgs) { Hook 'Test-LoopGuardrails.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; toolName = $Tool; toolArgs = $ToolArgs } }
function Decision($r) { if ($r.Contains('permissionDecision')) { $r.permissionDecision } else { 'none' } }
function Write-File([string]$Rel, [string]$Content) { [System.IO.File]::WriteAllText((Join-Path $raiz $Rel), $Content, $utf8) }
function State([string]$Id) { Get-Content (Join-Path $raiz "loops\$Id\loop-state.json") -Raw | ConvertFrom-Json -AsHashtable }

$specRefinada = @'
# Spec refinada — teste
## 3. Stack e estrutura
| Item | Definição |
|---|---|
| Linguagem/runtime | PowerShell |
## 6. Fluxos lógicos
| ID | Gatilho | Caminho | Resultado esperado |
|---|---|---|---|
| FL-01 | entrada válida | soma | total |
## 10. Comandos técnicos
| Etapa | Comando |
|---|---|
| restore | - |
| build | `echo build` |
| test | `echo test` |
| coverage | `echo coverage --threshold 100` |
| smoke | `echo smoke` |
'@

function New-Dod([string]$Id) {
    $tpl = Get-Content (Join-Path $raiz "loops\$Id\02-definicao-de-pronto.md") -Raw
    $tpl = $tpl.Replace('| DOD-01 | <preencher> | <preencher> | <preencher> | <preencher> | <preencher> | <preencher> |',
        "| DOD-01 | regra de negócio | Soma correta | 3 | Sim | teste automatizado | RN-01, FL-01 |`n| DOD-02 | qualidade | Log estruturado | 1 | Não | inspeção | - |")
    $tpl.Replace('- <preencher ou "Nada declarado">', '- Nada declarado')
}

function New-Plan([int]$N, [string[]]$Refs, [switch]$SemRef, [string]$Marca = ' ') {
    $nn = '{0:D2}' -f $N
    $itens = for ($i = 0; $i -lt $Refs.Count; $i++) {
        $ref = if ($SemRef) { '' } else { " · DoD: $($Refs[$i])" }
        "- [$Marca] P-$nn-{0:D2} — Implementar parte $i$ref" -f ($i + 1)
    }
    "# Plano`n`n## Escopo de escrita`n`n- src/feature/**`n- tests/feature/**`n`n## Checklist`n`n" + ($itens -join "`n") + "`n"
}

function New-Verification([string]$Id, [hashtable]$Scores) {
    Import-Module (Join-Path $scripts 'LoopCommon.psm1') -Force
    $crit = Get-DodCriteria $Id
    $linhas = foreach ($c in $crit.Keys) {
        $s = if ($Scores.ContainsKey($c)) { $Scores[$c] } elseif ($Scores.ContainsKey('*')) { $Scores['*'] } else { '0' }
        $ev = if ($s -ne '0') { 'teste X passou' } else { '-' }
        "| $c | 1 | Sim | $s | $ev | ok |"
    }
    "# Verificação`n`n| Critério | Peso | Gate | Pontuação | Evidência | Justificativa |`n|---|---|---|---|---|---|`n" + ($linhas -join "`n") + "`n"
}

try {
    Write-Host "`n== Raiz de teste: $raiz" -ForegroundColor Cyan

    Write-Host "`n== 1. INTAKE / REFINE / GATE_DOD"
    $r = Run 'Initialize-Loop.ps1' @{ Nome = 'Soma Simples'; SpecText = 'Somar dois números.' }
    $id = $r.loop_id
    Assert ($id -eq 'loop-soma-simples') 'Initialize-Loop cria id normalizado'
    Assert ((State $id).fase -eq 'REFINE') 'Fase inicial após INTAKE é REFINE'
    Assert (Test-Path (Join-Path $raiz 'loops\.active')) 'loops/.active criado'
    Throws 'Initialize-Loop.ps1' @{ Nome = 'outro'; SpecText = 'x' } 'loop ativo' 'Impede segundo loop ativo'
    Throws 'Set-LoopPhase.ps1' @{ Fase = 'GATE_DOD' } 'preencher' 'GATE_DOD recusa placeholders'
    Throws 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' } 'Transição inválida' 'Transição inválida REFINE -> IMPLEMENT'

    $d = Guard 'edit' @{ path = "loops/$id/02-definicao-de-pronto.md" }
    Assert ((Decision $d) -eq 'none') 'Refiner pode editar DoD antes do congelamento'
    $d = Guard 'edit' @{ path = 'src/feature/app.ps1' }
    Assert ((Decision $d) -eq 'deny') 'Código bloqueado na fase REFINE'

    Write-File "loops/$id/01-spec-refinada.md" $specRefinada
    Write-File "loops/$id/02-definicao-de-pronto.md" (New-Dod $id)
    $r = Run 'Set-LoopPhase.ps1' @{ Fase = 'GATE_DOD' }
    Assert ($r.aguardando_humano -eq $true) 'GATE_DOD aguarda humano'
    $c = Hook 'Test-LoopContinuation.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; stopReason = 'end_turn' }
    Assert (-not $c.Contains('decision')) 'agentStop libera em GATE_DOD'

    Write-Host "`n== 2. Aprovação da DoD e iteração 1"
    $r = Run 'Approve-LoopDod.ps1' @{ AprovadoPor = 'tester' }
    Assert ($r.fase -eq 'PLAN' -and $r.iteracao -eq 1) 'Aprovação abre iteração 1 em PLAN'
    Assert ($r.criterios -eq 16 -and $r.gates -eq 13) 'DoD com 16 critérios e 13 gates'
    $st = State $id
    Assert ($st.dod.congelada -and $st.comandos.build -eq 'echo build' -and $st.comandos.coverage -like '*100*') 'DoD congelada e comandos técnicos congelados'
    Assert (Test-Path (Join-Path $raiz "loops\$id\iteracao-01\planejamento-iteracao-01.md")) 'Templates da iteração 01 criados'

    $d = Guard 'edit' @{ path = "loops/$id/02-definicao-de-pronto.md" }
    Assert ((Decision $d) -eq 'deny') 'DoD congelada bloqueada para edição'
    $d = Guard 'create' @{ path = "loops/$id/loop-state.json" }
    Assert ((Decision $d) -eq 'deny') 'loop-state.json bloqueado para edição direta'
    $d = Guard 'edit' @{ path = '.github/hooks/loop-guardrails.json' }
    Assert ((Decision $d) -eq 'deny') 'Configuração de hooks protegida'
    $d = Guard 'edit' @{ path = "loops/$id/iteracao-01/planejamento-iteracao-01.md" }
    Assert ((Decision $d) -eq 'none') 'Plano da iteração corrente editável'
    $d = Guard 'create' @{ path = "loops/$id/iteracao-02/planejamento-iteracao-02.md" }
    Assert ((Decision $d) -eq 'deny') 'Iteração ainda não aberta bloqueada'
    $c = Hook 'Test-LoopContinuation.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; stopReason = 'end_turn' }
    Assert ($c.decision -eq 'block') 'agentStop força continuidade em PLAN'

    Write-Host "`n== 3. PLAN -> IMPLEMENT"
    Write-File "loops/$id/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 @('DOD-01', 'PT-04') -SemRef)
    Throws 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' } 'sem referência' 'Plano sem referência à DoD recusado'
    Write-File "loops/$id/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 @('DOD-01', 'DOD-99'))
    Throws 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' } 'inexistentes' 'Plano com critério inexistente recusado'
    Write-File "loops/$id/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 (1..16 | ForEach-Object { 'DOD-01' }))
    Throws 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' } 'máximo' 'Plano acima do limite de itens recusado'
    Write-File "loops/$id/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 @('DOD-01', 'PT-04'))
    $r = Run 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' }
    Assert (($r.escopo_escrita -join ',') -eq 'src/feature/**,tests/feature/**') 'Escopo de escrita registrado'

    Write-Host "`n== 4. Guard rails em IMPLEMENT"
    Assert ((Decision (Guard 'edit' @{ path = 'src/feature/app.ps1' })) -eq 'none') 'Escrita dentro do escopo permitida'
    Assert ((Decision (Guard 'create' @{ path = (Join-Path $raiz 'tests\feature\app.Tests.ps1') })) -eq 'none') 'Caminho absoluto dentro do escopo permitido'
    Assert ((Decision (Guard 'edit' @{ path = 'README.md' })) -eq 'deny') 'Escrita fora do escopo bloqueada'
    Assert ((Decision (Guard 'apply_patch' @{ input = "*** Begin Patch`n*** Update File: src/feature/a.ps1`n*** End Patch" })) -eq 'none') 'apply_patch dentro do escopo permitido'
    Assert ((Decision (Guard 'apply_patch' @{ input = "*** Begin Patch`n*** Add File: .github/hooks/x.json`n*** End Patch" })) -eq 'deny') 'apply_patch em área protegida bloqueado'
    Assert ((Decision (Guard 'view' @{ path = "loops/$id/loop-state.json" })) -eq 'none') 'Leitura nunca bloqueada'
    Assert ((Decision (Guard 'powershell' @{ command = 'git push origin main' })) -eq 'deny') 'git push bloqueado'
    Assert ((Decision (Guard 'powershell' @{ command = 'Remove-Item -Recurse -Force src' })) -eq 'deny') 'Remoção recursiva fora da allowlist bloqueada'
    Assert ((Decision (Guard 'powershell' @{ command = 'Remove-Item -Recurse -Force bin, obj' })) -eq 'none') 'Remoção recursiva de bin/obj permitida'
    Assert ((Decision (Guard 'powershell' @{ command = "Set-Content loops/$id/loop-state.json '{}'" })) -eq 'deny') 'Escrita via shell no estado bloqueada'
    Assert ((Decision (Guard 'powershell' @{ command = "Get-Content loops/$id/loop-state.json" })) -eq 'none') 'Leitura via shell do estado permitida'
    Assert ((Decision (Guard 'powershell' @{ command = 'pwsh -File .github/skills/loop-protocol/scripts/Get-LoopStatus.ps1' })) -eq 'none') 'Scripts do protocolo permitidos'
    Assert ((Decision (Guard 'powershell' @{ command = 'curl https://example.com' })) -eq 'deny') 'Comando restrito negado com loop em andamento (sem aprovação humana no meio do ciclo)'
    Assert ((Decision (Guard 'powershell' @{ command = 'dotnet test' })) -eq 'none') 'Comando de teste permitido'

    Write-Host "`n== 5. IMPLEMENT -> CHECK -> VERIFY -> DECIDE (continuar)"
    Throws 'Set-LoopPhase.ps1' @{ Fase = 'CHECK' } 'não executados' 'CHECK recusado com itens pendentes'
    Write-File "loops/$id/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 @('DOD-01', 'PT-04') -Marca 'x')
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'CHECK' }
    Assert ((Decision (Guard 'edit' @{ path = 'src/feature/app.ps1' })) -eq 'deny') 'Código bloqueado na fase CHECK'
    Throws 'Set-LoopPhase.ps1' @{ Fase = 'VERIFY' } 'Status geral' 'VERIFY recusado sem status da checagem'
    Write-File "loops/$id/iteracao-01/checagem-iteracao-01.md" "# Checagem`n`nStatus geral: VERMELHO`n"
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'VERIFY' }
    Write-File "loops/$id/iteracao-01/verificacao-iteracao-01.md" (New-Verification $id @{ 'DOD-01' = '0,5'; 'PT-01' = '1'; 'PT-02' = '1' })
    $r = Run 'Invoke-LoopDecision.ps1'
    Assert ($r.decisao -eq 'CONTINUAR' -and $r.proxima_iteracao -eq 2) 'Decisão CONTINUAR abre iteração 2'
    Assert ($r.indice -gt 0 -and $r.indice -lt 0.5) "Índice parcial calculado ($($r.indice))"
    Assert ('DOD-01' -in $r.gates_pendentes -and 'PT-04' -in $r.gates_pendentes) 'Gates pendentes identificados'
    Assert ((Decision (Guard 'edit' @{ path = "loops/$id/iteracao-01/planejamento-iteracao-01.md" })) -eq 'deny') 'Iteração fechada imutável'

    Write-Host "`n== 6. Iteração 2 até DONE"
    Write-File "loops/$id/iteracao-02/planejamento-iteracao-02.md" (New-Plan 2 @('DOD-01', 'PT-04') -Marca 'x')
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' }
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'CHECK' }
    Write-File "loops/$id/iteracao-02/checagem-iteracao-02.md" "# Checagem`n`nStatus geral: VERDE`n"
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'VERIFY' }
    $semEvid = (New-Verification $id @{ '*' = '1' }).Replace('| DOD-02 | 1 | Sim | 1 | teste X passou |', '| DOD-02 | 1 | Sim | 1 | - |')
    Write-File "loops/$id/iteracao-02/verificacao-iteracao-02.md" $semEvid
    $m = & (Join-Path $raiz '.github\skills\dod-scoring\scripts\Measure-Adherence.ps1') | ConvertFrom-Json -AsHashtable
    Assert ($m.pronto -and $m.indice -lt 1 -and ($m.alertas -join ' ') -match 'sem evidência') 'Pontuação sem evidência vale 0 (gate não afetado: DOD-02 é desejável)'
    Write-File "loops/$id/iteracao-02/verificacao-iteracao-02.md" (New-Verification $id @{ '*' = '1' })
    $r = Run 'Invoke-LoopDecision.ps1'
    Assert ($r.decisao -eq 'CONCLUIR' -and $r.status -eq 'DONE' -and $r.indice -eq 1) 'Decisão CONCLUIR com índice 1'
    Assert (-not (Test-Path (Join-Path $raiz 'loops\.active'))) 'loops/.active removido após DONE'
    Assert (Test-Path (Join-Path $raiz "loops\$id\resultado-final.md")) 'resultado-final.md gerado'
    Assert ((Decision (Guard 'edit' @{ path = 'README.md' })) -eq 'none') 'Sem loop ativo, hooks não interferem'

    Write-Host "`n== 7. Escalonamento por limite, retomada e aborto"
    $r = Run 'Initialize-Loop.ps1' @{ Nome = 'limite'; SpecText = 'x'; MaxIteracoes = 1 }
    $id2 = $r.loop_id
    Write-File "loops/$id2/01-spec-refinada.md" $specRefinada
    Write-File "loops/$id2/02-definicao-de-pronto.md" (New-Dod $id2)
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'GATE_DOD' }
    $null = Run 'Approve-LoopDod.ps1' @{ AprovadoPor = 'tester' }
    Write-File "loops/$id2/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 @('DOD-01') -Marca 'x')
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' }
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'CHECK' }
    Write-File "loops/$id2/iteracao-01/checagem-iteracao-01.md" "Status geral: VERDE`n"
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'VERIFY' }
    Write-File "loops/$id2/iteracao-01/verificacao-iteracao-01.md" (New-Verification $id2 @{ '*' = '1'; 'PT-04' = '0' })
    $r = Run 'Invoke-LoopDecision.ps1'
    Assert ($r.status -eq 'ESCALATED' -and $r.motivo -eq 'LIMITE_ITERACOES') 'Escala por limite de iterações'
    $st = State $id2
    Assert ($st.parada.fase -eq 'DECIDE' -and $st.parada.iteracao -eq 1) 'Ponto de parada registrado (DECIDE, iteração 1)'
    Assert ((Decision (Guard 'powershell' @{ command = 'curl https://example.com' })) -eq 'ask') 'Comando restrito pede confirmação com o loop parado'
    $c = Hook 'Test-LoopContinuation.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; stopReason = 'end_turn' }
    Assert (-not $c.Contains('decision')) 'agentStop libera em ESCALATED'
    $s = Hook 'Write-HookEvent.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; transcriptPath = ''; agentName = 'loop-planner' } @('-Evento', 'subagentStart')
    Assert ($s.additionalContext -match 'BLOQUEADO PELO HARNESS') 'subagentStart injeta bloqueio quando escalado'
    $r = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Continuar'; AutorizadoPor = 'tester'; IteracoesExtras = 1; Motivo = 'teste' }
    Assert ($r.iteracao -eq 2 -and $r.max_iteracoes -eq 2) 'Retomada amplia limite e abre iteração 2'
    $s = Hook 'Write-HookEvent.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; transcriptPath = ''; agentName = 'loop-planner' } @('-Evento', 'subagentStart')
    Assert ($s.additionalContext -match 'Fase: PLAN' -and $s.additionalContext -notmatch 'BLOQUEADO') 'subagentStart injeta contexto do loop'
    $null = Hook 'Write-HookEvent.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; transcriptPath = ''; agentName = 'loop-planner'; agentId = '1'; agentType = 'loop-planner'; response = 'abc'; stopReason = 'end_turn' } @('-Evento', 'subagentStop')
    $null = Hook 'Write-HookEvent.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; toolName = 'edit'; toolArgs = @{ path = 'src/feature/a.ps1' }; toolResult = @{ resultType = 'success'; textResultForLlm = 'ok' } } @('-Evento', 'postToolUse')
    $log = Get-Content (Join-Path $raiz "loops\$id2\log.jsonl") | ForEach-Object { $_ | ConvertFrom-Json }
    Assert (@($log | Where-Object acao -eq 'SUBAGENTE_FIM' | Where-Object { $null -ne $_.duracao_ms }).Count -ge 1) 'subagentStop registra duração'
    Assert (@($log | Where-Object { $_.acao -eq 'FERRAMENTA_EXECUTADA' -and $_.alvo -eq 'src/feature/a.ps1' }).Count -eq 1) 'postToolUse registra ferramenta e alvo'
    $md = & (Join-Path $scripts 'Get-LoopStatus.ps1')
    Assert ($md -match 'Curva de convergência' -and $md -match 'Próxima ação') 'Get-LoopStatus em Markdown'
    $r = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Abortar'; AutorizadoPor = 'tester'; Motivo = 'fim do teste' }
    Assert ($r.status -eq 'ABORTED' -and -not (Test-Path (Join-Path $raiz 'loops\.active'))) 'Aborto encerra e desativa o loop'
    $todos = & (Join-Path $scripts 'Get-LoopStatus.ps1') -Todos
    Assert ($todos -match 'loop-soma-simples' -and $todos -match 'loop-limite') 'Get-LoopStatus -Todos lista loops'

    $eventos = Get-Content (Join-Path $raiz "loops\$id\log.jsonl") | ForEach-Object { $_ | ConvertFrom-Json }
    Assert (@($eventos | Where-Object acao -eq 'GUARDRAIL_BLOQUEIO').Count -ge 10) "Bloqueios registrados no log ($(@($eventos | Where-Object acao -eq 'GUARDRAIL_BLOQUEIO').Count))"
    Assert (@($eventos | Where-Object acao -eq 'INDICE_CALCULADO').Count -eq 2) 'Índices registrados por iteração'

    Write-Host "`n== 8. Estagnação, oscilação e regressão"
    function New-ApprovedLoop([string]$Nome) {
        $rr = Run 'Initialize-Loop.ps1' @{ Nome = $Nome; SpecText = 'x' }
        Write-File "loops/$($rr.loop_id)/01-spec-refinada.md" $specRefinada
        Write-File "loops/$($rr.loop_id)/02-definicao-de-pronto.md" (New-Dod $rr.loop_id)
        $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'GATE_DOD' }
        $null = Run 'Approve-LoopDod.ps1' @{ AprovadoPor = 'tester' }
        $rr.loop_id
    }
    function Invoke-Iteration([string]$LoopId, [string[]]$Refs, [hashtable]$Scores) {
        $n = (State $LoopId).iteracao_atual
        $nn = '{0:D2}' -f $n
        Write-File "loops/$LoopId/iteracao-$nn/planejamento-iteracao-$nn.md" (New-Plan $n $Refs -Marca 'x')
        $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' }
        $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'CHECK' }
        Write-File "loops/$LoopId/iteracao-$nn/checagem-iteracao-$nn.md" "Status geral: VERMELHO`n"
        $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'VERIFY' }
        Write-File "loops/$LoopId/iteracao-$nn/verificacao-iteracao-$nn.md" (New-Verification $LoopId $Scores)
        Run 'Invoke-LoopDecision.ps1'
    }

    $idE = New-ApprovedLoop 'estagnacao'
    $r1 = Invoke-Iteration $idE @('DOD-02') @{ '*' = '1'; 'PT-04' = '0' }
    $r2 = Invoke-Iteration $idE @('DOD-02') @{ '*' = '1'; 'PT-04' = '0' }
    $r3 = Invoke-Iteration $idE @('DOD-02') @{ '*' = '1'; 'PT-04' = '0' }
    Assert ($r1.decisao -eq 'CONTINUAR' -and $r2.decisao -eq 'CONTINUAR' -and $r3.motivo -eq 'ESTAGNACAO') "Escala por estagnação na 3ª iteração ($($r3.motivo))"
    $null = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Abortar'; AutorizadoPor = 'tester' }

    $idO = New-ApprovedLoop 'oscilacao'
    $null = Invoke-Iteration $idO @('PT-04') @{ '*' = '0' }
    $null = Invoke-Iteration $idO @('PT-04') @{ '*' = '1'; 'PT-04' = '0'; 'PT-03' = '0' }
    $r3 = Invoke-Iteration $idO @('PT-04') @{ '*' = '1'; 'PT-04' = '0' }
    Assert ($r3.motivo -eq 'OSCILACAO') "Escala por oscilação (mesmo critério planejado falhando 3x) ($($r3.motivo))"
    $null = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Abortar'; AutorizadoPor = 'tester' }

    $idR = New-ApprovedLoop 'regressao'
    $null = Invoke-Iteration $idR @('DOD-02') @{ '*' = '1'; 'PT-04' = '0' }
    $r2 = Invoke-Iteration $idR @('DOD-02') @{ '*' = '1'; 'PT-04' = '0'; 'PT-03' = '0' }
    $r3 = Invoke-Iteration $idR @('DOD-02') @{ '*' = '1'; 'PT-04' = '0'; 'PT-03' = '0'; 'PT-09' = '0' }
    Assert ($r2.decisao -eq 'CONTINUAR' -and ($r2.alertas -join ' ') -match 'REGRESSAO') 'Primeira regressão gera alerta e continua'
    Assert ($r3.motivo -eq 'REGRESSAO') "Escala por regressões consecutivas ($($r3.motivo))"
    $null = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Abortar'; AutorizadoPor = 'tester' }

    Write-Host "`n== 9. Parada no meio de uma fase e retomada do ponto exato"
    $idP = New-ApprovedLoop 'parada'
    Write-File "loops/$idP/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 @('DOD-01', 'PT-04'))
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' }
    $r = Run 'Stop-Loop.ps1' @{ Motivo = 'IMPEDIMENTO'; Detalhe = 'SDK ausente' }
    $st = State $idP
    Assert ($st.status -eq 'ESCALATED' -and $st.parada.fase -eq 'IMPLEMENT' -and $st.parada.iteracao -eq 1 -and @($st.escopo_escrita_atual).Count -eq 0) 'Stop-Loop registra parada em IMPLEMENT e fecha o escopo'
    Assert (Test-Path (Join-Path $raiz "loops\$idP\resultado-final.md")) 'resultado-final.md gerado na parada sem iteração avaliada'
    $c = Hook 'Test-LoopContinuation.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; stopReason = 'end_turn' }
    Assert (-not $c.Contains('decision')) 'agentStop libera com o loop parado'
    $md = & (Join-Path $scripts 'Get-LoopStatus.ps1')
    Assert ($md -match 'Ponto de parada \| IMPLEMENT, iteração 1') 'Status mostra o ponto de parada'
    $r = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Continuar'; AutorizadoPor = 'tester'; Motivo = 'SDK instalado' }
    $st = State $idP
    Assert ($r.fase -eq 'IMPLEMENT' -and $r.iteracao -eq 1 -and $st.iteracao_atual -eq 1) 'Retomada volta para IMPLEMENT na mesma iteração'
    Assert ((($st.escopo_escrita_atual) -join ',') -eq 'src/feature/**,tests/feature/**') 'Escopo de escrita restaurado a partir do plano'
    Assert ((Decision (Guard 'edit' @{ path = 'src/feature/app.ps1' })) -eq 'none') 'Implementação liberada após a retomada'
    Assert ($null -eq $st.parada -and @($st.paradas).Count -eq 1 -and $st.paradas[0].retomado_por -eq 'tester') 'Parada movida para o histórico de paradas'

    for ($i = 1; $i -le 3; $i++) { $c = Hook 'Test-LoopContinuation.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; stopReason = 'end_turn' } }
    Assert ($c.decision -eq 'block') 'agentStop força continuidade nas 3 primeiras tentativas'
    $null = Hook 'Test-LoopContinuation.ps1' @{ sessionId = 't'; timestamp = 0; cwd = $raiz; stopReason = 'end_turn' }
    $st = State $idP
    Assert ($st.status -eq 'ESCALATED' -and $st.motivo_encerramento -eq 'ORQUESTRADOR_INTERROMPIDO' -and $st.parada.fase -eq 'IMPLEMENT') 'Orquestrador que para repetidamente dispara parada automática'
    $r = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Continuar'; AutorizadoPor = 'tester' }
    Assert ($r.fase -eq 'IMPLEMENT' -and @((State $idP).paradas).Count -eq 2) 'Segunda retomada volta ao mesmo ponto'

    Write-File "loops/$idP/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 @('DOD-01', 'PT-04') -Marca 'x')
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'CHECK' }
    $null = Run 'Stop-Loop.ps1' @{ Motivo = 'FALHA_PROTOCOLO'; Detalhe = 'checker falhou 2x' }
    $r = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Continuar'; AutorizadoPor = 'tester' }
    Assert ($r.fase -eq 'CHECK' -and $r.iteracao -eq 1) 'Parada em CHECK retoma em CHECK'
    Write-File "loops/$idP/iteracao-01/checagem-iteracao-01.md" "Status geral: VERDE`n"
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'VERIFY' }
    Write-File "loops/$idP/iteracao-01/verificacao-iteracao-01.md" (New-Verification $idP @{ '*' = '1' })
    $r = Run 'Invoke-LoopDecision.ps1'
    Assert ($r.decisao -eq 'CONCLUIR' -and $r.status -eq 'DONE') 'Loop retomado chega a DONE'
    Throws 'Stop-Loop.ps1' @{ Motivo = 'IMPEDIMENTO'; Detalhe = 'x'; LoopId = $idP } 'em andamento' 'Stop-Loop recusa loop encerrado'

    Write-Host "`n== 10. D-17: contrato imutável e nova versão do loop"
    $idC = New-ApprovedLoop 'contrato'
    Write-File "loops/$idC/iteracao-01/planejamento-iteracao-01.md" (New-Plan 1 @('DOD-01'))
    $null = Run 'Set-LoopPhase.ps1' @{ Fase = 'IMPLEMENT' }
    $null = Run 'Stop-Loop.ps1' @{ Motivo = 'AMBIGUIDADE_REGRA'; Detalhe = 'RN-01 não define arredondamento' }
    Throws 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Continuar'; AutorizadoPor = 'tester'; Motivo = 'arredondar para cima' } 'D-17' 'Parada de contrato não admite retomada no mesmo loop'
    $md = & (Join-Path $scripts 'Get-LoopStatus.ps1')
    Assert ($md -match 'Motivo de contrato \(D-17\)' -and $md -match 'LoopAnterior') 'Próxima ação orienta abortar e abrir nova versão'
    Throws 'Initialize-Loop.ps1' @{ Nome = 'contrato-v2'; SpecText = 'RN-01: arredondar para baixo'; LoopAnterior = $idC } 'encerrado' 'Nova versão exige o loop anterior encerrado'
    $null = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Abortar'; AutorizadoPor = 'tester'; Motivo = 'regra será decidida' }
    $r = Run 'Initialize-Loop.ps1' @{ Nome = 'contrato-v2'; SpecText = 'RN-01: arredondar para baixo, 2 casas'; LoopAnterior = $idC }
    $spec00 = Get-Content (Join-Path $raiz "loops\$($r.loop_id)\00-spec-original.md") -Raw
    Assert ($r.loop_id -eq 'loop-contrato-v2' -and $r.loop_anterior -eq $idC -and (State $r.loop_id).fase -eq 'REFINE') 'Nova versão iniciada em REFINE, vinculada ao loop anterior'
    Assert ($spec00 -match 'AMBIGUIDADE_REGRA' -and $spec00 -match 'arredondar para baixo' -and $spec00 -match 'Fluxos lógicos') 'Spec da nova versão = decisão + spec refinada anterior'
    Assert ((State $idC).substituido_por -eq 'loop-contrato-v2') 'Loop anterior aponta para a nova versão'
    $null = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Abortar'; AutorizadoPor = 'tester' }

    $idI = New-ApprovedLoop 'integridade'
    $null = Run 'Stop-Loop.ps1' @{ Motivo = 'IMPEDIMENTO'; Detalhe = 'ambiente' }
    $dodPath = Join-Path $raiz "loops\$idI\02-definicao-de-pronto.md"
    $original = Get-Content $dodPath -Raw
    [System.IO.File]::WriteAllText($dodPath, $original.Replace('| DOD-02 | qualidade | Log estruturado | 1 | Não |', '| DOD-02 | qualidade | Log estruturado | 1 | Sim |'), $utf8)
    Throws 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Continuar'; AutorizadoPor = 'tester'; Motivo = 'x' } 'artefatos congelados alterados' 'Retomada recusada com DoD alterada durante a parada'
    [System.IO.File]::WriteAllText($dodPath, $original, $utf8)
    $r = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Continuar'; AutorizadoPor = 'tester'; Motivo = 'ambiente corrigido' }
    Assert ($r.fase -eq 'PLAN' -and $r.iteracao -eq 1) 'Retomada aceita após restaurar a DoD aprovada'
    $null = Run 'Resolve-LoopEscalation.ps1' @{ Decisao = 'Abortar'; AutorizadoPor = 'tester' }
} catch {
    $script:falhas.Add("Exceção não esperada: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)")
    Write-Host $_ -ForegroundColor Red
} finally {
    Write-Host "`n== Resultado: $($script:ok) OK, $($script:falhas.Count) falha(s)" -ForegroundColor $(if ($script:falhas.Count) { 'Red' } else { 'Green' })
    foreach ($f in $script:falhas) { Write-Host "   - $f" -ForegroundColor Red }
    if ($Manter) { Write-Host "Pasta mantida: $raiz" } else { Remove-Item $raiz -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($script:falhas.Count) { exit 1 }
