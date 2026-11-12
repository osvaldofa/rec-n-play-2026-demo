---
name: dod-scoring
description: 'Rubrica e cálculo do índice de aderência à Definição de Pronto (DoD): pontuação 0/0,5/1 com evidência obrigatória, pesos e gates, condição de pronto, cobertura 100% de fluxo lógico e regras anti-gamificação. Use when: verificar implementação contra a DoD, pontuar critérios, montar matriz de rastreabilidade, calcular índice de aderência (Measure-Adherence).'
user-invocable: false
---

# DoD Scoring

## Quando usar
- Na fase **VERIFY**, pelo `loop-verifier`, para pontuar cada critério da DoD com evidência.
- Na fase **DECIDE**, pelo `Invoke-LoopDecision.ps1`, que chama o script de cálculo.
- Pelo `loop-refiner`, ao escrever critérios verificáveis.

## Procedimento de verificação
1. Leia a DoD congelada (`02-definicao-de-pronto.md`) e confira o hash SHA-256 com `dod.hash_sha256` em `loop-state.json`.
2. Leia a checagem da iteração (`checagem-iteracao-NN.md`).
3. Para **cada** critério (`DOD-xx` e `PT-xx`), colete a evidência pelo método definido e pontue seguindo a [rubrica](./rubrica.md).
4. Monte a matriz de rastreabilidade: cada `FL`/`RN`/`CE`/`CS` da spec refinada ligado aos testes que o referenciam (PT-05).
5. Registre as execuções reais do código (PT-09) com o comando, a saída resumida e o contrato esperado.
6. Liste as recomendações objetivas para o próximo plano, priorizando os gates pendentes.

## Cálculo

```powershell
pwsh -NoProfile -File .github/skills/dod-scoring/scripts/Measure-Adherence.ps1 [-LoopId <id>] [-Iteracao <n>]
```

- **Índice** = Σ(peso × pontuação) / Σ(peso). Os pesos e gates vêm **sempre da DoD**.
- **Pronto** ⇔ CHECK VERDE ∧ todos os gates = 1 ∧ índice ≥ limiar ∧ DoD íntegra.
- Os casos abaixo valem 0 e geram alerta:
  - pontuação ausente ou inválida;
  - pontuação > 0 sem evidência.

## Referências
- [rubrica.md](./rubrica.md): rubrica, exigências de evidência, cobertura de fluxo lógico e anti-gamificação.
