# Prompt 07 — Relatório executivo e demonstração

> **Prompt 8 de 8.** Requer tudo o que veio antes. É o que fecha o projeto.

---

Leia `.llm/prd.md`. Último prompt. Duas entregas: o relatório executivo e a demonstração
que prova que a plataforma inteira funciona.

## 1. Relatório executivo (RF-08)

Um notebook que responde, para uma região e um dia:

> Resuma o que aconteceu em Campinas nas últimas 24 horas e diga o que precisa de ação hoje.

**Lê apenas a camada gold** (RN-13). Nenhuma linha toca bronze ou silver.

O que ele precisa reunir:

- **Operação por conjunto** no dia: interrupções, horas-UC, maior evento, causa
  predominante, chamados, negativos, risco à saúde
- **O dia contra a normalidade.** Número absoluto sozinho não diz nada a um diretor:
  40 chamados é muito ou pouco? Compare com a média dos 30 dias anteriores. É o que
  transforma contagem em informação.
- **Continuidade do mês**, vinda da metric view com `MEASURE()`
- **O que precisa de ação hoje**, incluindo bairros com UCs em prioridade alta e clientes
  em risco de ouvidoria

**O dia de referência é o último dia com movimento no painel**, não `current_date()`. Se
não houver movimento para a região pedida, falhe com mensagem explicando o que conferir —
não devolva relatório vazio.

### O texto final

Redigido por `ai_gen`, com duas amarras explícitas no prompt:

1. **Use exclusivamente os números fornecidos.** Não estime, não arredonde para efeito, não
   invente valor.
2. **UCs com consumo atípico são prioridade de inspeção.** Nunca escreva fraude, furto,
   roubo ou irregularidade.

Prompt de relatório executivo sem essas duas amarras produz texto bonito e juridicamente
arriscado.

Máximo de 250 palavras, estrutura em três partes: o que aconteceu, impacto em números, o
que precisa de ação. Tom direto, sem adjetivo de marketing — quem lê tem dois minutos.

**Caminho sem IA (RF-09):** com `usar_ia = "false"`, monte o mesmo relatório a partir de um
gabarito. Os números são idênticos nos dois caminhos; muda a prosa, não o fato.

Adicione o notebook como task final do job do medalhão.

## 2. As queries que provam a plataforma

Escreva um notebook ou arquivo SQL de demonstração, com uma consulta para cada afirmação
que o projeto faz. Cada uma acompanhada do resultado esperado:

| # | O que prova | Consulta |
|---|---|---|
| 1 | **RN-01 tem efeito** | Contagem de interrupções na bronze contra a silver, e o percentual descartado |
| 2 | **A qualidade tem efeito** | Linhas de consumo na bronze contra a silver, por motivo de descarte |
| 3 | **RN-04 é real** | O mesmo DEC vindo da metric view e o cálculo manual a partir dos insumos — têm de bater |
| 4 | **Os dois eixos funcionam** | As UCs em prioridade alta, com a variação delas e a variação do conjunto lado a lado |
| 5 | **A anonimização funciona** | Uma transcrição da bronze e a mesma da silver, lado a lado |
| 6 | **O evento narrativo está lá** | Chamados por hora na noite da cascata, contra a média das mesmas horas nos outros dias |
| 7 | **A tendência está lá** | Consumo total por ano — tem de crescer ~30% ao ano |
| 8 | **A sazonalidade está lá** | Chamados por mês — verão tem de ficar perto do dobro |

As duas últimas são as que só existem porque o dataset tem quatro anos. Num trimestre,
nenhuma das duas seria visível.

## 3. Feche o repositório

- **README** com: o que o projeto é, pré-requisitos, o perfil da CLI, a sequência de
  comandos do zero ao copiloto, a estrutura de pastas e as regras que valem repetir
- **AGENTS.md** com as convenções para quem for continuar o projeto com um agente
- Confirme que `databricks bundle validate` e o lint passam

## Ao terminar

Rode o job completo e me mostre:

1. O relatório executivo gerado
2. O resultado das oito queries de demonstração
3. O link do dashboard e o do Genie space

## Critério de aceite

- O relatório reconstrói a história de Campinas cruzando as três bases
- O texto não contém nenhum número que não esteja nos dados
- O texto não usa as palavras fraude, furto ou irregularidade
- As oito queries rodam e devolvem o resultado esperado
- `bundle validate` e lint passam
- Um analista que abre o repositório pela primeira vez entende o que fazer pelo README
