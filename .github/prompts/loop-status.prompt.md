---
name: loop-status
description: "Mostra o status de um loop de engenharia (fase, iteração, curva de convergência do índice de aderência, gates pendentes, bloqueios de guard rail e próxima ação) ou lista todos os loops."
agent: agent
tools: [execute, read]
argument-hint: "[loop-id | todos]"
---

Consulte o status, **somente leitura**, sem avançar o loop nem editar arquivos.

1. Execute na raiz do repositório:
   - `pwsh -NoProfile -File .github/skills/loop-protocol/scripts/Get-LoopStatus.ps1 -LoopId <id>`, se um loop for informado;
   - `... Get-LoopStatus.ps1 -Todos`, se o usuário pedir "todos";
   - `... Get-LoopStatus.ps1` sem parâmetros, para o loop ativo ou a lista.
2. Apresente o Markdown retornado.
3. Acrescente uma interpretação curta (até 3 linhas):
   - tendência do índice;
   - principais gates pendentes;
   - o que o usuário precisa decidir, se houver.
