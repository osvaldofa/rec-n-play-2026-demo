# Especificações de entrada

Coloque aqui as specs que darão origem a loops. Cada arquivo vira a `00-spec-original.md` de um loop.

## Como iniciar um loop

No chat do VS Code (sessão **Copilot**):

```
/loop-start minha-funcionalidade specs/minha-funcionalidade.md
```

Parâmetros opcionais: `max-iteracoes=N` e `limiar=0.9`.

## O que uma boa spec contém

Use [TEMPLATE-spec.md](./TEMPLATE-spec.md) como ponto de partida. O loop refina a spec, mas quanto mais claros estes pontos, melhor a Definição de Pronto:

1. **Objetivo:** o problema resolvido e para quem.
2. **Entradas:** dados recebidos, formatos e validações conhecidas.
3. **Comportamento:** regras de negócio e casos de erro esperados.
4. **Saídas:** formato de sucesso e de erro.
5. **Restrições:** stack desejada, onde o código deve ficar, limites não-funcionais.
6. **Exemplos:** pelo menos um caso de sucesso e um de erro, com entrada e saída.
