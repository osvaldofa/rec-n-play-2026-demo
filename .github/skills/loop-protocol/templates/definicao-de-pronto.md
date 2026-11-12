# Definição de pronto — {{LOOP_ID}}

> Contrato do loop. Produzida pelo `loop-refiner`, aprovada e congelada por um humano no GATE_DOD.
> Limiar de aderência: **{{LIMIAR}}** · Pesos: 1 (baixo), 2 (médio), 3 (alto) · Gate: `Sim` exige pontuação 1.
> Pronto ⇔ CHECK VERDE ∧ todos os gates = 1 ∧ índice ≥ limiar.

## Critérios funcionais

> Cada critério deve ser **verificável** e rastrear IDs da spec refinada (`CE`, `RN`, `FL`, `CS`).
> Métodos: `teste automatizado` · `execução real` · `inspeção` · `contrato/esquema`.

| ID | Tipo | Descrição verificável | Peso | Gate | Método | Rastreio |
|---|---|---|---|---|---|---|
| DOD-01 | <preencher> | <preencher> | <preencher> | <preencher> | <preencher> | <preencher> |

## Padrões técnicos herdados

> Baseline obrigatória (seção 8 do documento base). Pode ser **endurecida**; afrouxar exige justificativa na coluna "Ajuste neste loop" e aprovação humana.

| ID | Padrão | Peso | Gate | Método | Ajuste neste loop |
|---|---|---|---|---|---|
| PT-01 | Build sem erros e sem warnings (warnings como erro) | 3 | Sim | Checker: saída do build | — |
| PT-02 | Lint/format sem violações | 2 | Sim | Checker: saída do linter | — |
| PT-03 | 100% dos testes passando, nenhum ignorado/skip | 3 | Sim | Checker: relatório de testes | — |
| PT-04 | Cobertura 100% de linhas e branches no escopo lógico | 3 | Sim | Checker: relatório de cobertura | — |
| PT-05 | Rastreabilidade 100%: todo FL/RN/CE/CS com ≥ 1 teste | 3 | Sim | Verifier: matriz de rastreabilidade | — |
| PT-06 | Cada regra de validação de entrada com teste positivo e negativo | 2 | Sim | Verifier: testes de CE-xx | — |
| PT-07 | Contratos de saída testados para sucesso e erro | 2 | Sim | Verifier: testes de CS-xx | — |
| PT-08 | Testes determinísticos (2 execuções, mesmo resultado) | 2 | Sim | Checker: execução dupla | — |
| PT-09 | Execução real (smoke) do fluxo principal | 3 | Sim | Verifier: execução do código | — |
| PT-10 | Sem segredos, TODO/FIXME ou código comentado no escopo | 2 | Sim | Checker: varredura | — |
| PT-11 | Análise estática sem achados alta/crítica | 2 | Sim | Checker: analisador | — |
| PT-12 | Dependências sem vulnerabilidades alta/crítica | 2 | Não | Checker: auditoria | — |
| PT-13 | Documentação de uso atualizada conforme contratos | 1 | Não | Verifier: inspeção | — |
| PT-14 | Exclusões e limiares de cobertura iguais aos aprovados | 3 | Sim | Verifier: inspeção da configuração | — |

## Fora de escopo

- <preencher ou "Nada declarado">
