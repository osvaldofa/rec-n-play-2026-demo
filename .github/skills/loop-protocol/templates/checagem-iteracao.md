# Checagem — iteração {{ITERACAO}} · {{LOOP_ID}}

> Produzida pelo `loop-checker` executando os comandos congelados em `loop-state.json`.
> A linha "Status geral" é lida pelos scripts: use exatamente `VERDE` ou `VERMELHO`.

Status geral: <VERDE|VERMELHO>

| Etapa | Comando | Status | Resultado |
|---|---|---|---|
| Restore | <comando ou -> | <VERDE/VERMELHO/N/A> | <resumo> |
| Build | <comando> | <VERDE/VERMELHO> | <erros, warnings> |
| Lint | <comando ou -> | <VERDE/VERMELHO/N/A> | <violações> |
| Testes | <comando> | <VERDE/VERMELHO> | <passaram/total, ignorados> |
| Cobertura | <comando> | <VERDE/VERMELHO> | <linhas % · branches %> |
| Determinismo | 2ª execução dos testes | <VERDE/VERMELHO> | <idêntica?> |
| Varredura (segredos/TODO/código comentado) | <comando> | <VERDE/VERMELHO> | <achados> |
| Análise estática | <comando ou -> | <VERDE/VERMELHO/N/A> | <achados alta/crítica> |
| Auditoria de dependências | <comando ou -> | <VERDE/VERMELHO/N/A> | <vulnerabilidades> |

## Falhas relevantes

<trechos curtos e objetivos dos erros; não colar logs inteiros>

## Arquivos/linhas sem cobertura

<lista de arquivos e linhas/branches não cobertos, se houver>
