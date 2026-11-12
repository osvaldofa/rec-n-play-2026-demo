# Spec — Inscrições em workshop com lista de espera
 
## Identificação
 
- **Nome do loop:** inscricoes-lista-espera
- **Solicitante:** organização de eventos
- **Tipo:** funcionalidade nova (sistema pequeno, do zero)
## Objetivo
 
Permitir que pessoas se inscrevam num workshop com vagas limitadas. Quando as vagas acabarem,
novos interessados entram numa lista de espera, para não serem perdidos. Se alguém desistir,
a próxima pessoa da lista é chamada e avisada.
 
## Contexto
 
O organizador hoje controla inscrições numa planilha e perde interessados quando o workshop lota.
Ele quer uma tela simples, usada no próprio navegador, onde consiga:
 
- inscrever uma pessoa pelo nome;
- ver quem está confirmado e quem está esperando;
- cancelar a inscrição de alguém;
- ver quem foi chamado da lista de espera e confirmar a vaga dessa pessoa.
## Comportamento esperado
 
1. O workshop tem um número fixo de vagas, definido ao criá-lo.
2. Enquanto houver vaga, a inscrição é confirmada na hora.
3. Sem vaga, a pessoa entra na lista de espera, em ordem de chegada.
4. Não pode haver inscrição duplicada.
5. Quando um confirmado cancela, a primeira pessoa da lista de espera é chamada e recebe um aviso.
   Ela tem 24 horas para confirmar; enquanto isso, a vaga fica reservada para ela.
6. A pessoa chamada pode confirmar a vaga dentro do prazo.
7. A tela mostra três listas: confirmados, chamados aguardando confirmação (com o prazo) e lista de espera.
## Restrições
 
- **Sem infraestrutura externa:** nada de rede, e-mail, SMS, banco de dados ou serviços de terceiros.
  "Avisar" significa um aviso dentro da própria aplicação.
- **Estado em memória:** os dados vivem enquanto a aplicação está aberta. Sem persistência.
- **Tempo controlado:** o domínio recebe um relógio injetado. É proibido usar `Date.now()`,
  `setTimeout` ou `setInterval` no domínio, para que prazos sejam testáveis e os testes, determinísticos.
- **Sem dependências npm:** apenas Node.js 22+ e o navegador.
- **Identificação:** a pessoa é identificada só pelo nome. Sem login.
## Stack e organização sugeridas
 
| Parte | Caminho | Observação |
| --- | --- | --- |
| Domínio | `src/inscricoes.js` | Regras de negócio. Sem DOM, sem I/O, sem timers |
| Tela | `src/render.js` | Recebe o estado e devolve HTML (string). Testável em Node |
| Página | `web/index.html` | Liga a tela ao domínio; estado em memória da página; botão para avançar o relógio simulado |
| Servidor local | `web/serve.mjs` | Servidor estático com `node:http`, só para abrir a página no navegador |
| Smoke | `src/smoke.mjs` | Executa o fluxo principal de ponta a ponta em Node e sai com código 0 se tudo der certo |
| Testes | `tests/**/*.test.mjs` | `node:test` + `node:assert` |
 
## Comandos técnicos sugeridos
 
| Etapa | Comando |
| --- | --- |
| Build | `node --check src/inscricoes.js && node --check src/render.js && node --check src/smoke.mjs` |
| Testes | `node --test "tests/**/*.test.mjs"` |
| Cobertura | `node --test --experimental-test-coverage --test-coverage-lines=100 --test-coverage-branches=100 --test-coverage-include="src/**" --test-coverage-exclude="src/smoke.mjs" "tests/**/*.test.mjs"` |
| Smoke | `node src/smoke.mjs` |
 
> O comando de cobertura falha (código de saída diferente de zero) quando linhas ou branches ficam abaixo de 100%.
> Atenção: a cobertura nativa do Node só mede arquivos que os testes importam. Um arquivo de `src/` sem nenhum
> teste não aparece no relatório e não reprova o limite. A DoD precisa de um critério que garanta que todo arquivo
> do escopo lógico é importado por pelo menos um teste.
> Sem dependências npm não há linter: o PT-02 precisa de um ajuste explícito, a ser decidido no GATE_DOD.
 
## Fora de escopo
 
- Envio de e-mail, SMS ou notificação externa.
- Persistência, exportação ou importação de dados.
- Autenticação, perfis e permissões.
- Mais de um workshop ao mesmo tempo.
- Layout responsivo ou acessibilidade avançada (a tela é para demonstração).