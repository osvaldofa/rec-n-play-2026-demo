# Instruções do repositório

Este repositório contém um modelo de **loop engineering**: loops agênticos que partem de uma especificação e iteram até atingir a Definição de Pronto. O desenho completo está em `loop-engineering-base.md`.

## Estrutura
- `.github/agents/`: orquestrador (`loop-orchestrator`) e subagentes de fase (`loop-refiner`, `loop-planner`, `loop-implementer`, `loop-checker`, `loop-verifier`).
- `.github/prompts/`: entradas `/loop-start`, `/loop-resume` e `/loop-status`.
- `.github/skills/`:
  - `loop-protocol`: protocolo, scripts, templates e esquemas;
  - `dod-scoring`: rubrica e cálculo do índice.
- `.github/hooks/`: guard rails e observabilidade (ativos apenas com um loop ativo em `loops/.active`).
- `.github/loop-config.json`: limites, caminhos protegidos e padrões de comandos.
- `specs/`: especificações de entrada para novos loops.
- `loops/`: execução dos loops (processo). O código produzido vai para pastas próprias do produto (ex.: `src/`, `tests/`).

## Convenções
- Idioma: português do Brasil.
- Os scripts exigem PowerShell 7+ (`pwsh`).
- A stack e os comandos técnicos (build, testes, cobertura e smoke) são definidos **por loop**, na spec refinada. Depois da aprovação da DoD, ficam congelados em `loop-state.json`.
- Para validar o harness, execute `pwsh -NoProfile -File .github/skills/loop-protocol/tests/Test-LoopHarness.ps1`.
