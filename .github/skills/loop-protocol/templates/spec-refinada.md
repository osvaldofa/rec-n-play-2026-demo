# Spec refinada — {{LOOP_ID}}

> Produzida pelo `loop-refiner` a partir de `00-spec-original.md`.
> Congelada junto com a DoD após aprovação humana (GATE_DOD).
> Remova todos os marcadores `<preencher ...>` antes de solicitar o gate.

## 1. Objetivo

<preencher: objetivo da funcionalidade em 2–4 frases>

## 2. Contexto, premissas e restrições

- <preencher: premissa ou restrição>

## 3. Stack e estrutura

| Item | Definição |
|---|---|
| Linguagem/runtime | <preencher> |
| Framework de testes | <preencher> |
| Ferramenta de cobertura | <preencher> |
| Pasta de código | <preencher: ex. src/feature-x/> |
| Pasta de testes | <preencher: ex. tests/feature-x/> |

## 4. Contratos de entrada

| ID | Campo | Tipo | Obrigatório | Regras de validação |
|---|---|---|---|---|
| CE-01 | <preencher> | <preencher> | <preencher> | <preencher> |

## 5. Regras de negócio

| ID | Regra | Exemplo |
|---|---|---|
| RN-01 | <preencher> | <preencher> |

## 6. Fluxos lógicos

> Liste todos os caminhos relevantes, inclusive erros e bordas. Cada `FL-xx` precisa de ao menos um teste que o referencie (PT-05).

| ID | Gatilho | Caminho | Resultado esperado |
|---|---|---|---|
| FL-01 | <preencher> | <preencher> | <preencher> |

## 7. Contratos de saída

| ID | Situação | Formato | Exemplo |
|---|---|---|---|
| CS-01 | Sucesso | <preencher> | <preencher> |
| CS-02 | Erro | <preencher> | <preencher> |

## 8. Escopo lógico (cobertura 100%)

- **Incluído:** <preencher: globs do código com lógica>
- **Excluído:** nenhum
  <!-- Formato: `glob` — justificativa. Código excluído não pode conter decisão (if/switch/ternário/laço condicional/try com lógica). -->

## 9. Convenção de rastreabilidade nos testes

<preencher: como os testes referenciam IDs — ex. nome `FL01_...`, atributo `[Trait("spec","FL-01")]`, `describe('FL-01 ...')` ou comentário `// spec: FL-01`>

## 10. Comandos técnicos

> Congelados no estado do loop na aprovação da DoD. `build`, `test`, `coverage` e `smoke` são obrigatórios.
> O comando de `coverage` deve falhar abaixo de 100% de linhas **e** branches no escopo lógico.

| Etapa | Comando |
|---|---|
| restore | <preencher ou -> |
| build | <preencher> |
| lint | <preencher ou -> |
| test | <preencher> |
| coverage | <preencher> |
| static_analysis | <preencher ou -> |
| dependency_audit | <preencher ou -> |
| smoke | <preencher> |

## 11. Questões em aberto

- Nenhuma.
