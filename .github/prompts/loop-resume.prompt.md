---
name: loop-resume
description: "Retoma um loop de engenharia do ponto onde parou, ou registra a decisão humana fora do ciclo: aprovar a DoD, pedir ajustes, retomar após uma condição de parada ou abortar."
agent: loop-orchestrator
argument-hint: "[loop-id] [aprovar | ajustar: <o que mudar> | continuar [+N]: <orientação técnica> | abortar: <motivo> | nova versão: <decisão sobre a regra>]"
---

Retome o loop de engenharia indicado. Sem loop informado, use o loop ativo (`loops/.active`).

1. Execute `Get-LoopStatus.ps1 -Formato Json` (skill `loop-protocol`) e identifique o `status`, a `fase`, a `parada` (se houver) e a `proxima_acao`.
2. Se a mensagem trouxer uma **decisão humana**, aplique-a conforme o protocolo do orquestrador:

   | Decisão | Quando se aplica | Script |
   |---|---|---|
   | **aprovar** | GATE_DOD | `Approve-LoopDod.ps1 -AprovadoPor <usuário>` |
   | **ajustar: ...** | GATE_DOD | `Set-LoopPhase.ps1 -Fase REFINE -Motivo "..."` e refinar novamente |
   | **continuar [+N]: ...** | ESCALATED por motivo operacional ou de convergência | `Resolve-LoopEscalation.ps1 -Decisao Continuar [-IteracoesExtras N] -Motivo "..."`. Retoma da fase e iteração onde o loop parou. A orientação é técnica (ambiente, dependências, abordagem) e não altera regras nem critérios (D-17) |
   | **abortar: ...** | qualquer fase | `Resolve-LoopEscalation.ps1 -Decisao Abortar -Motivo "..."` |
   | **nova versão: <decisão sobre a regra>** | ESCALATED por motivo de contrato (`AMBIGUIDADE_REGRA`, `CONTESTACAO_CRITERIO`) | Abortar e depois `Initialize-Loop.ps1 -Nome <nome>-v2 -LoopAnterior <loop-id> -SpecText "<decisão>"`. Segue para REFINE e para um novo GATE_DOD |

3. Sem decisão humana:
   - em GATE_DOD ou ESCALATED, reapresente o resumo (no caso de parada: motivo, fase, iteração e evidência) e informe as opções;
   - com o loop em andamento (por exemplo, sessão interrompida), continue o protocolo a partir da fase registrada, sem perguntas, até o próximo gate, uma parada ou o encerramento.
