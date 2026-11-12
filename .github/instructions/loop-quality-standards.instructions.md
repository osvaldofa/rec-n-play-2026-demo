---
description: "Padrões técnicos de qualidade do loop de engenharia (PT-01..PT-14): cobertura 100% de linhas e branches no escopo lógico, rastreabilidade de fluxos lógicos para testes, testes de contrato de entrada/saída, determinismo, smoke, anti-gamificação. Use when: implementar, testar, checar ou verificar código dentro de um loop de engenharia."
---

# Padrões técnicos do loop (baseline herdada por toda DoD)

A baseline completa está em `02-definicao-de-pronto.md`, na tabela "Padrões técnicos herdados". Uma DoD pode **endurecer** os padrões. Para **afrouxá-los**, precisa de aprovação humana registrada.

## Cobertura de 100% do fluxo lógico
- **Estrutural (PT-04):** 100% de **linhas** e de **branches** no escopo lógico declarado na spec refinada (seção "Escopo lógico").
- **Rastreabilidade (PT-05):** todo `FL-xx`, `RN-xx`, `CE-xx` e `CS-xx` precisa de ao menos um teste que o referencie pelo ID. Siga a convenção definida na spec refinada (nome do teste, atributo/tag ou comentário `spec: FL-01`).
- **Exclusões de cobertura:**
  - só valem as listadas e justificadas na spec refinada aprovada;
  - o código excluído **não pode conter decisão**.

## Ao implementar (loop-implementer)
- Escreva o teste **junto com** o código de cada `FL`/`RN`/`CE`/`CS` e referencie o ID no teste.
- **Contratos de entrada (PT-06):** para cada regra de validação, um teste positivo **e** um negativo.
- **Contratos de saída (PT-07):** teste o formato de sucesso **e** o de erro.
- **Determinismo (PT-08):** isole rede, relógio e aleatoriedade (injeção de dependência, fakes, seeds fixas).
- **Não faça:**
  - deixar `TODO`, `FIXME`, código comentado ou segredos (PT-10);
  - usar `skip`/ignore em testes (PT-03);
  - alterar limiares, configuração ou exclusões de cobertura (PT-14). Os hooks bloqueiam essas alterações após a aprovação da DoD;
  - remover ou enfraquecer asserções existentes sem um item do plano que justifique.
- Trate warnings como erros (PT-01) e respeite o lint (PT-02).

## Ao checar (loop-checker)
- Execute **exatamente** os comandos congelados em `loop-state.json` → `comandos`.
- Rode os testes duas vezes e compare os resultados (PT-08).
- Reporte os números de cobertura (linhas e branches) e os arquivos/linhas não cobertos.

## Ao verificar (loop-verifier)
- Siga a rubrica da skill `dod-scoring`.
- Sem evidência, a pontuação é 0.
- Testes triviais ou sem asserção também valem 0.

## Ferramental de referência

| Stack | Cobertura (falha < 100% em linhas e branches) |
|---|---|
| .NET | coverlet: `dotnet test /p:CollectCoverage=true /p:Threshold=100 /p:ThresholdType=line%2cbranch` |
| Node/TS | Vitest `coverage.thresholds` / Jest `coverageThreshold` = 100 em `lines` e `branches` |
| Python | `pytest --cov=<pkg> --cov-branch --cov-fail-under=100` |
| Java | JaCoCo `check` com `LINE` e `BRANCH` `COVEREDRATIO` = 1.0 |
