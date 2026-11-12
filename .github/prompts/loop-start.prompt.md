---
name: loop-start
description: "Inicia um novo loop de engenharia a partir de uma especificação (arquivo em specs/ ou texto): cria a estrutura, refina a spec, gera a Definição de Pronto e para no gate de aprovação humana."
agent: loop-orchestrator
argument-hint: "<nome-do-loop> <caminho da spec, ex.: specs/minha-funcionalidade.md> [max-iteracoes=5] [limiar=0.9] [anterior=<loop-id>]"
---

Inicie um **novo loop de engenharia** com os dados informados pelo usuário nesta mensagem.

1. Identifique:
   - **nome do loop:** se ausente, derive do nome do arquivo da spec;
   - **spec:** caminho de arquivo, preferencialmente em `specs/`, ou texto livre;
   - **limites opcionais:** `max-iteracoes`, `limiar`;
   - **loop anterior opcional** (`anterior=<loop-id>`): nova versão de um contrato. A spec informada é a decisão sobre a regra alterada, e a base é a spec refinada do loop anterior (D-17).
2. Sem spec, peça ao usuário o caminho ou o texto e pare.
3. Execute `Initialize-Loop.ps1` (skill `loop-protocol`) e conduza a fase **REFINE**.
4. Valide com `Set-LoopPhase.ps1 -Fase GATE_DOD` e apresente o resumo para o **gate de aprovação da DoD**.
5. Encerre o turno aguardando a decisão do usuário (aprovar, ajustar ou abortar). Não aprove em nome do usuário.
