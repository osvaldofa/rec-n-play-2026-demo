# Verificação — iteração {{ITERACAO}} · {{LOOP_ID}}

> Produzida pelo `loop-verifier` (sem permissão de edição de código).
> Pontuação: `1` atende · `0,5` parcial · `0` não atende. **Sem evidência = 0.**
> Pesos e gates são lidos da DoD pelo script `Measure-Adherence.ps1`; as colunas Peso/Gate aqui são informativas.

Hash da DoD conferido: <OK|DIVERGENTE>

## Matriz de aderência

| Critério | Peso | Gate | Pontuação | Evidência | Justificativa |
|---|---|---|---|---|---|
| DOD-01 | <peso> | <Sim/Não> | <0/0,5/1> | <teste, comando+saída, arquivo:linha> | <por que esta pontuação> |

## Matriz de rastreabilidade (PT-05)

| ID da spec | Testes que o referenciam |
|---|---|
| FL-01 | <teste(s)> |

## Execuções realizadas (PT-09)

| Cenário | Comando | Resultado observado | Esperado (contrato) |
|---|---|---|---|
| <cenário> | <comando> | <saída resumida> | <CS-xx> |

## Resumo

- Gates pendentes (na avaliação do verificador): <lista>
- Recomendação para o próximo plano: <itens prioritários>

> O índice oficial é calculado por `Measure-Adherence.ps1` na fase DECIDE e registrado em `loop-state.json` e `log.jsonl`.
