# A sequência de 8 prompts

Cada arquivo desta pasta é um **prompt pronto para colar no Claude Code**. Juntos, eles
constroem a Grid Intelligence do zero — do catálogo vazio ao copiloto respondendo perguntas
de diretoria.

| # | Arquivo | Entrega | Resultado visível |
|---|---|---|---|
| 00 | [`00-setup.md`](00-setup.md) | Contexto, regras de negócio, schemas e volume | Catálogo com as quatro camadas e os dados no volume |
| 01 | [`01-bronze.md`](01-bronze.md) | Ingestão fiel | Quatro tabelas bronze e o painel de qualidade acusando os defeitos |
| 02 | [`02-silver-numeros.md`](02-silver-numeros.md) | Cadastro, RN-01, dedup e baseline | Quantas interrupções a regra dos 3 minutos descartou |
| 03-A | [`03-silver-texto-ia.md`](03-silver-texto-ia.md) | Anonimização e enriquecimento com IA | Transcrição antes e depois do mascaramento |
| 03-B | [`03-silver-texto-regex.md`](03-silver-texto-regex.md) | **Ou:** o mesmo, com regex e `CASE` | As mesmas colunas, em segundos |
| 04 | [`04-gold.md`](04-gold.md) | As quatro entregas e a metric view | DEC e FEC por conjunto, saindo de uma definição só |
| 05 | [`05-dashboard.md`](05-dashboard.md) | Painel AI/BI | Dashboard de duas páginas |
| 06 | [`06-agente.md`](06-agente.md) | Copiloto conversacional | O agente respondendo sobre Campinas |
| 07 | [`07-relatorio-e-demonstracao.md`](07-relatorio-e-demonstracao.md) | Relatório executivo e provas | Uma página para a diretoria e oito queries |

## O prompt 03 tem duas versões — escolha uma

**É o único ponto da sequência onde a IA entra no pipeline de dados**, e é onde ela custa
caro: cada função de IA é uma inferência por linha, e com 2.801 chamados e quatro funções
na cadeia são ~11 mil chamadas ao modelo. A execução pode levar dezenas de minutos —
suficiente para travar uma aula ao vivo.

| | 03-A, com IA | 03-B, com regex |
|---|---|---|
| Tempo | dezenas de minutos | segundos |
| Qualidade da extração | entende o texto | pega o que casa com o padrão |
| Reprodutibilidade | varia entre execuções | idêntica sempre |

As duas produzem **as mesmas colunas** e cumprem RN-09 e RN-10. Por isso o prompt 04 em
diante — gold, dashboard, agente e relatório — funciona igual, sem saber qual rota você
escolheu.

Use o **03-A** quando quiser mostrar IA no pipeline; o **03-B** quando o tempo mandar, ou
quando o workspace não tiver as funções `ai_*` disponíveis.

## Como usar

1. Abra o Claude Code no repositório
2. Cole o prompt inteiro, do começo ao fim
3. Deixe ele trabalhar, revise, faça o deploy e **veja o resultado**
4. Só então passe para o próximo

Não pule a ordem. Cada prompt assume o anterior pronto e diz explicitamente o que **não**
deve ser feito ainda — é o que impede o agente de tentar construir o projeto inteiro de uma
vez e entregar tudo pela metade.

## Por que prompt e não issue

Cada um desses arquivos carrega três coisas que um ticket comum não carrega:

- **a regra de negócio junto do pedido** — o agente não precisa adivinhar por que o limiar
  é 3 minutos
- **as armadilhas conhecidas** — baseline sobre série com tendência, streaming table
  append-only, `execCommand` fora do gesto do usuário
- **o critério de aceite** — o que precisa ser verdade para a etapa estar pronta

## Reaproveitando em outro projeto

A sequência é o template: **setup → ingestão → limpeza → enriquecimento → negócio →
visualização → agente → prova**. Trocar o domínio significa reescrever o prompt 00 inteiro
e ajustar os nomes de tabela nos demais. A estrutura, as armadilhas técnicas e o formato
com critério de aceite continuam valendo.
