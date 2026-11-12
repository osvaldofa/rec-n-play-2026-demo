---
description: "Convenções dos artefatos de loop de engenharia (spec refinada, definição de pronto, planejamento, checagem, verificação, logs) em loops/."
applyTo: "loops/**"
---

# Convenções dos artefatos de loop

- **Idioma:** português do Brasil. IDs e nomes de arquivo sem acento.
- **Estrutura de um loop:** `loops/loop-<nome>/` contém `loop-state.json`, `log.jsonl`, `00-spec-original.md`, `01-spec-refinada.md`, `02-definicao-de-pronto.md`, `iteracao-NN/` e `resultado-final.md`.
- **IDs:** `CE-xx` (entrada), `RN-xx` (regra), `FL-xx` (fluxo lógico), `CS-xx` (saída), `DOD-xx` (critério funcional), `PT-xx` (padrão técnico), `P-NN-xx` (item do plano). Use dois dígitos, por exemplo `FL-03` e `P-02-07`.
- **Somente os scripts alteram:** `loop-state.json`, `log.jsonl`, `loops/.active` e `00-spec-original.md`. Os scripts ficam em `.github/skills/loop-protocol/scripts/`.
- **Imutáveis:**
  - spec refinada e DoD, depois da aprovação no GATE_DOD;
  - pastas de iterações anteriores à atual.
- **Estrutura que os scripts leem** (não altere nomes de seção nem colunas):
  - **Plano:**
    - itens no formato `- [ ] P-NN-xx — <ação> · DoD: <DOD-xx|PT-xx> · Arquivos: <...> · Pronto quando: <...>`;
    - a seção `## Escopo de escrita`, com globs em lista.
  - **Checagem:** a linha `Status geral: VERDE` ou `Status geral: VERMELHO`.
  - **Verificação:** tabela `Critério | Peso | Gate | Pontuação | Evidência | Justificativa`, com pontuação `0`, `0,5` ou `1`.
  - **DoD:** tabelas com as colunas `ID`, `Peso` (1–3) e `Gate` (`Sim`/`Não`).
  - **Spec refinada:** tabela `Etapa | Comando` na seção "Comandos técnicos".
- **Marcação do checklist:**

  | Marca | Significado |
  |---|---|
  | `[x]` | concluído |
  | `[~]` | concluído com desvio (registre o desvio no log da iteração) |
  | `[!]` | bloqueado (registre o motivo) |

- **Log narrativo** (`log-iteracao-NN.md`): entradas `- [HH:mm] [agente] texto` nas seções Decisões, Desvios, Bloqueios e Premissas. Registre o **porquê**. O **quê** já é gravado pelos hooks em `log.jsonl`.
- **Placeholders:** não deixe `<preencher` nos artefatos. O gate recusa a transição enquanto houver algum.
