---
name: loop-protocol
description: 'Protocolo do loop de engenharia orientado a especificação: máquina de estados, scripts de transição (Initialize-Loop, Set-LoopPhase, Approve-LoopDod, Invoke-LoopDecision, Resolve-LoopEscalation), templates de artefatos (spec refinada, definição de pronto, planejamento, checagem, verificação, log) e esquemas de estado/log. Use when: iniciar, retomar, avançar ou consultar um loop em loops/, preencher artefatos de iteração, registrar eventos no log.jsonl.'
user-invocable: false
---

# Loop Protocol

Protocolo que conduz um loop de engenharia: da spec ao `DONE`, ou ao `ESCALATED` quando um guard rail dispara.
**Toda mudança de estado passa pelos scripts abaixo.** O `loop-state.json`, o `log.jsonl`, o `loops/.active` e a `00-spec-original.md` são protegidos pelos hooks contra edição direta.

## Máquina de estados

```
INTAKE → REFINE → GATE_DOD ⇄ REFINE
GATE_DOD → (aprovação humana) → PLAN → IMPLEMENT → CHECK → VERIFY → DECIDE
DECIDE → PLAN (nova iteração) | DONE | ESCALATED
qualquer fase em andamento → (Stop-Loop / hook) → ESCALATED
ESCALATED → (humano retoma) → fase e iteração onde parou | ABORTED
```

**Princípio:** dentro do ciclo, ninguém humano aprova ou avalia nada. Quem avalia é o próprio loop (checker, verifier e scripts). O humano atua só no GATE_DOD, quando uma condição de parada é disparada (para retomar ou abortar) e na revisão da entrega.

## Scripts

Execute sempre a partir da raiz do repositório:

```powershell
pwsh -NoProfile -File .github/skills/loop-protocol/scripts/<Script>.ps1 <parâmetros>
```

Todos retornam JSON no stdout e lançam erro com mensagem clara quando a transição é inválida.

| Script | Quando | Efeito |
|---|---|---|
| [Initialize-Loop.ps1](./scripts/Initialize-Loop.ps1) `-Nome <n> -SpecPath <arq>` ou `-SpecText <txt>` `[-MaxIteracoes n] [-Limiar 0.9] [-LoopAnterior <id>]` | INTAKE | Cria `loops/loop-<n>/`, grava spec original, templates 01/02, estado e log; ativa o loop; fase → REFINE. Com `-LoopAnterior` (D-17), a spec é a refinada do loop anterior mais a decisão informada |
| [Set-LoopPhase.ps1](./scripts/Set-LoopPhase.ps1) `-Fase GATE_DOD` | Após o refinamento | Valida que não restam `<preencher`, que existem DOD-xx e os PT obrigatórios; marca `aguardando_humano` |
| `Set-LoopPhase.ps1 -Fase REFINE -Motivo "<ajustes>"` | O humano pede ajustes no gate | Volta para REFINE |
| [Approve-LoopDod.ps1](./scripts/Approve-LoopDod.ps1) `-AprovadoPor <usuário>` | **Somente com aprovação explícita do humano** | Congela spec e DoD (hash), congela os comandos técnicos, abre `iteracao-01` em PLAN |
| `Set-LoopPhase.ps1 -Fase IMPLEMENT` | Após persistir o plano | Valida o checklist (IDs, refs à DoD, limite de itens) e registra o **escopo de escrita** |
| `Set-LoopPhase.ps1 -Fase CHECK` | Após a implementação | Exige todos os itens marcados (`[x]`, `[~]`, `[!]`); fecha o escopo de escrita |
| `Set-LoopPhase.ps1 -Fase VERIFY` | Após persistir a checagem | Exige `Status geral: VERDE\|VERMELHO` |
| [Invoke-LoopDecision.ps1](./scripts/Invoke-LoopDecision.ps1) | Após persistir a verificação | Calcula o índice, aplica o algoritmo de decisão e executa a transição (nova iteração, DONE ou ESCALATED) |
| [Stop-Loop.ps1](./scripts/Stop-Loop.ps1) `-Motivo IMPEDIMENTO\|FALHA_PROTOCOLO\|AMBIGUIDADE_REGRA\|CONTESTACAO_CRITERIO -Detalhe <causa>` | O loop não consegue prosseguir sozinho | Condição de parada: ESCALATED, com a fase e a iteração exatas registradas em `parada` |
| [Resolve-LoopEscalation.ps1](./scripts/Resolve-LoopEscalation.ps1) `-Decisao Continuar\|Abortar -AutorizadoPor <usuário> [-IteracoesExtras n]` | **Somente por decisão humana**, com o loop parado | Retoma do ponto de parada (DECIDE abre a próxima iteração; outra fase volta para a mesma fase e iteração) ou aborta. Recusa `Continuar` para motivos de contrato e para artefatos congelados alterados (D-17) |
| [Get-LoopStatus.ps1](./scripts/Get-LoopStatus.ps1) `[-LoopId] [-Formato Markdown\|Json] [-Todos]` | A qualquer momento | Resumo, curva de convergência e **próxima ação** |
| [Write-LoopEvent.ps1](./scripts/Write-LoopEvent.ps1) `-Acao NOTA\|DECISAO_AGENTE\|DESVIO\|BLOQUEIO\|PREMISSA\|ALERTA\|ARTEFATO_GRAVADO -Agente <nome>` | Eventos que os hooks não capturam | Grava uma linha no `log.jsonl` |
| [Set-ActiveLoop.ps1](./scripts/Set-ActiveLoop.ps1) `-LoopId <id>` ou `-Desativar` | Trocar ou desligar o loop ativo | Os hooks só atuam com um loop ativo |

## Artefatos e templates

| Artefato | Template | Autor | Persistido por |
|---|---|---|---|
| `01-spec-refinada.md` | [spec-refinada.md](./templates/spec-refinada.md) | loop-refiner | loop-refiner |
| `02-definicao-de-pronto.md` | [definicao-de-pronto.md](./templates/definicao-de-pronto.md) | loop-refiner | loop-refiner |
| `iteracao-NN/planejamento-iteracao-NN.md` | [planejamento-iteracao.md](./templates/planejamento-iteracao.md) | loop-planner | orquestrador |
| `iteracao-NN/checagem-iteracao-NN.md` | [checagem-iteracao.md](./templates/checagem-iteracao.md) | loop-checker | orquestrador |
| `iteracao-NN/verificacao-iteracao-NN.md` | [verificacao-iteracao.md](./templates/verificacao-iteracao.md) | loop-verifier | orquestrador |
| `iteracao-NN/log-iteracao-NN.md` | [log-iteracao.md](./templates/log-iteracao.md) | todos | quem escreve |
| `resultado-final.md` | [resultado-final.md](./templates/resultado-final.md) | script + orquestrador | script / orquestrador |

Os templates da iteração são criados automaticamente quando a iteração é aberta. Substitua o conteúdo e **mantenha a estrutura que os scripts leem**:
- **Plano:** itens `- [ ] P-NN-xx — ... · DoD: DOD-xx` e a seção `## Escopo de escrita` com globs em lista.
- **Checagem:** linha `Status geral: VERDE` ou `Status geral: VERMELHO`.
- **Verificação:** tabela com as colunas `Critério | Peso | Gate | Pontuação | Evidência | Justificativa`.
- **DoD:** tabelas com as colunas `ID`, `Peso` e `Gate`.
- **Spec refinada:** tabela `Etapa | Comando` na seção "Comandos técnicos".

## Convenção de IDs

`CE-xx` contrato de entrada · `RN-xx` regra de negócio · `FL-xx` fluxo lógico · `CS-xx` contrato de saída ·
`DOD-xx` critério funcional · `PT-xx` padrão técnico · `P-NN-xx` item do plano da iteração NN.

## Esquemas

- [loop-state.schema.json](./schemas/loop-state.schema.json)
- [log-event.schema.json](./schemas/log-event.schema.json)

## Validação do harness

```powershell
pwsh -NoProfile -File .github/skills/loop-protocol/tests/Test-LoopHarness.ps1
```

Executa o ciclo completo e os hooks em uma cópia isolada (pasta temporária).
