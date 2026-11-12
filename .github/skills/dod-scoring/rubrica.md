# Rubrica de aderência à DoD

## Pontuação

| Pontuação | Significado | Evidência exigida |
|---|---|---|
| **1** | Atende plenamente | Objetiva e reproduzível: teste passando (nome), comando com saída, relatório (com números) ou `arquivo:linha` |
| **0,5** | Atende parcialmente | A evidência mostra cobertura incompleta. Exemplo: o caminho de sucesso está ok e o de erro está ausente |
| **0** | Não atende ou não há evidência | Sem evidência, a pontuação é 0, sem exceção |

- Um gate só é satisfeito com **1**. Nota 0,5 em um gate equivale a um gate pendente.
- Seja conservador: na dúvida entre duas notas, escolha a menor e explique na justificativa.
- A justificativa diz **por que** a nota não é maior (ou por que é a máxima).

## Evidências por método

| Método | Evidência válida |
|---|---|
| Teste automatizado | Nome(s) do(s) teste(s), arquivo e resultado na execução desta iteração |
| Execução real | Comando executado, entrada usada, saída observada (resumida) e o contrato `CS-xx` comparado |
| Inspeção | `arquivo:linha` e a descrição do que foi verificado |
| Contrato/esquema | Esquema/contrato comparado e o resultado da validação |

## Cobertura de 100% do fluxo lógico (PT-04 + PT-05)

1. **Estrutural (PT-04):** 100% de linhas **e** 100% de branches no escopo lógico declarado na spec refinada.
   - A evidência é o relatório da ferramenta, com os números de linhas e branches.
   - Um valor abaixo de 100%, em qualquer das duas medidas, vale **0**.
2. **Rastreabilidade (PT-05):** todo `FL-xx`, `RN-xx`, `CE-xx` e `CS-xx` tem ≥ 1 teste que o referencia, conforme a convenção da spec refinada.
   - A evidência é a matriz de rastreabilidade.
   - Qualquer ID sem teste faz o PT-05 valer **0**.
3. **Exclusões:** só valem as exclusões listadas e justificadas na spec refinada aprovada. O código excluído **não pode conter decisão** (`if`, `switch`, ternário, laço condicional ou `try` com lógica).

## Anti-gamificação (o verificador deve checar)

Cada situação abaixo leva o critério afetado a **0**:

| Situação detectada | Critério afetado |
|---|---|
| Teste sem asserção, ou com asserção trivial (`assert true`, `expect(1).toBe(1)`) | Critério testado |
| Teste marcado como ignorado/skip | PT-03 |
| Exclusões de cobertura além das aprovadas | PT-14 |
| Limiar de cobertura reduzido ou removido | PT-14 |
| Configuração de cobertura alterada após a aprovação | PT-14 |
| Hash da DoD divergente | **Toda a verificação**. Registre `Hash da DoD conferido: DIVERGENTE`; o loop escala por `INTEGRIDADE_DOD` |

Mais duas regras sobre testes:
- Remover ou enfraquecer asserções de testes existentes só é aceito se um item do plano da iteração justificar isso explicitamente.
- Testes que dependem de rede, relógio ou aleatoriedade sem controle não satisfazem PT-08.

## Condição de pronto

```
PRONTO ⇔ CHECK = VERDE ∧ todos os gates = 1 ∧ índice ≥ limiar ∧ DoD íntegra
```
