# Loops

Execuções dos loops de engenharia. Cada pasta `loop-<nome>/` é criada por `/loop-start` e contém o processo completo: spec, DoD, iterações, logs e resultado.

```
loop-<nome>/
├── loop-state.json            # estado (alterado só por scripts)
├── log.jsonl                  # eventos estruturados (hooks + scripts)
├── 00-spec-original.md        # entrada (imutável)
├── 01-spec-refinada.md        # contratos, regras, fluxos, comandos (congelada após o gate)
├── 02-definicao-de-pronto.md  # DOD-xx + PT-xx (congelada após o gate)
├── iteracao-NN/
│   ├── planejamento-iteracao-NN.md
│   ├── checagem-iteracao-NN.md
│   ├── verificacao-iteracao-NN.md
│   └── log-iteracao-NN.md
└── resultado-final.md
```

- **`.active`:** guarda o id do loop ativo. Os hooks de guard rail só atuam enquanto ele existe.
- **Desativar o loop ativo sem encerrá-lo:** `pwsh -File .github/skills/loop-protocol/scripts/Set-ActiveLoop.ps1 -Desativar`.
- **Consultar:** `/loop-status`. **Retomar:** `/loop-resume`.
