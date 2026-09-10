# PRD — Grid Intelligence

Documento de referencia para todos os prompts do projeto. Qualquer prompt seguinte
deve ler este arquivo antes de propor uma mudanca que contradiga o que esta aqui.

## Contexto de negocio

A **Luz do Vale Distribuidora S.A.** e uma distribuidora de energia eletrica ficticia,
regulada pela ANEEL. O projeto **Grid Intelligence** constroi a plataforma de dados e
IA da empresa no Databricks, endereçando tres dores mensuraveis em dinheiro:

1. **Continuidade do fornecimento.** Interromper alem do limite regulatorio gera
   compensacao financeira automatica ao consumidor. Em 2024 as distribuidoras
   brasileiras pagaram mais de R$ 1,1 bilhao em compensacoes.
2. **Perdas nao tecnicas.** Energia distribuida e nao faturada — furto, fraude e erro
   de medicao. Em 2025 somaram ~R$ 11,5 bilhoes, dos quais ~R$ 7,9 bilhoes foram
   repassados a tarifa.
3. **Atendimento ao cliente.** Milhares de ligacoes viram transcricao e ninguem le.
   Dentro delas esta o aviso antecipado da reclamacao na ouvidoria.

## Glossario

| Termo | Definicao |
|---|---|
| **UC — Unidade Consumidora** | O ponto de entrega de energia. Nao e sinonimo de cliente: um cliente pode ter varias UCs |
| **Conjunto** | Subdivisao geografica da area de concessao. E a unidade de agregacao do regulador |
| **DEC** | Duracao Equivalente de Interrupcao por UC — tempo medio, em horas, sem fornecimento |
| **FEC** | Frequencia Equivalente de Interrupcao por UC — numero medio de interrupcoes |
| **PNT** | Perdas Nao Tecnicas |
| **Prioridade de inspecao** | Classificacao de quanto uma UC merece visita tecnica |

## Regras de negocio

- **RN-01** — So interrupcoes com 3 minutos ou mais entram na apuracao de DEC e FEC.
  A regra vive na camada de transformacao, nunca no relatorio.
- **RN-04** — DEC e FEC tem uma unica definicao no sistema, consumida por dashboard,
  agente e relatorio.
- **RN-06** — Uma UC e candidata a inspecao quando o consumo cai em dois eixos
  simultaneos: contra o proprio baseline e enquanto a vizinhanca permanece estavel.
  So o primeiro eixo apontaria o bairro inteiro depois de um apagao.
- **RN-07** — A saida da deteccao e prioridade de inspecao — alta, media, baixa.
  Nunca um rotulo de fraude, furto ou culpa. Queda de consumo tambem e mudanca de
  morador, imovel desocupado, defeito de medidor e erro de leitura. Em setor regulado
  a diferenca e juridica. Nenhuma coluna, variavel ou comentario do projeto pode usar
  as palavras "fraude", "furto" ou "culpado" como rotulo de saida.
- **RN-09** — Dado pessoal em transcricao e mascarado antes de qualquer analise de
  conteudo.
- **RN-10** — O texto original identificado e preservado com acesso restrito. Duas
  protecoes que coexistem: uma na leitura, outra na analise.
- **RN-11** — A camada de ingestao nao filtra, nao corrige e nao aplica regra de
  negocio. Leitura invalida de medidor e um fato sobre o medidor. Filtrar na ingestao
  parece limpeza; e destruicao de evidencia.
- **RN-12** — Todo registro ingerido carrega origem e momento de ingestao.
- **RN-13** — O agente conversacional acessa apenas a camada de negocio.
- **RN-14** — As entidades da camada gold carregam descricao em linguagem de negocio —
  e o que o agente le. Bronze e silver nao precisam: sao passagem.

## Diretriz de simplicidade

Projeto construido ao vivo, em aula. Codigo que ninguem consegue ler na tela em dez
segundos nao serve, mesmo que seja mais robusto:

- Sem expectations e sem `CONSTRAINT` nas tabelas. Regra de negocio vira `WHERE`.
- Sem `COMMENT` em bronze e silver — sao passagem. So gold e metric view levam
  descricao (RN-14).
- Sem `TBLPROPERTIES`, `CLUSTER BY` e afins, a menos que sem eles quebre.
- Sem tratamento de caso que o dataset nao tem.
- Um `SELECT` direto vence um `WITH` de quatro CTEs.

## Convencoes

- Todo texto e nome em portugues do Brasil; nomes de entidades, colunas e arquivos
  sem acentuacao.
- Nenhum nome de catalogo fixado em codigo — vem de `${var.catalog}`. Nenhum nome de
  schema fixado — vem de `${resources.schemas.<camada>.name}`.
- Nenhum nome de modelo de IA fixado no codigo — usar as funcoes `ai_*` do Databricks.
- Perfil da CLI: `grid_intelligence`. Todo comando leva `--profile grid_intelligence`.

## Modelo de informacao

Camadas: `raw` (volume com os Parquet originais) -> `bronze` (ingestao fiel) ->
`silver` (regras de negocio, qualidade, dedup) -> `gold` (entregas de negocio,
consumidas pelo dashboard, agente e relatorio).

| Base | Grao | Volume | Observacoes |
|---|---|---|---|
| `unidades_consumidoras` | uma por ponto de entrega | 4.000 | cadastro de UC |
| `interrupcoes` | uma por evento de rede | 1.383 | inclui eventos abaixo de 3 min (RN-01) |
| `consumo_diario` | uma por UC por dia | ~5,85 milhoes (4 anos) | crescimento 30%/ano, defeitos propositais |
| `chamados` | uma por ligacao, com transcricao | 2.801 | sazonalidade de verao (dez-mar) |

O dataset carrega defeitos propositais — consumo nulo, negativo, fisicamente
impossivel, linhas duplicadas e interrupcoes abaixo de 3 minutos. Nao sao bug: existem
para as validacoes de qualidade e a RN-01 terem o que fazer.

## Catalogos e ambientes

| Ambiente | Catalogo | Uso |
|---|---|---|
| `dev` | `grid_dev` | dia a dia |
| `prod` | `grid_intelligence` | ambiente final, validado em dev |

Os schemas `raw`, `bronze`, `silver` e `gold` tem o mesmo nome nos dois catalogos —
o isolamento entre ambientes e feito pelo catalogo, nao pelo nome do schema.

## As quatro entregas de negocio previstas (camada gold)

1. **Continuidade** — DEC/FEC por conjunto, via metric view unica (RN-04).
2. **Priorizacao de inspecao** — UCs candidatas a inspecao por queda de consumo em
   dois eixos, com saida em prioridade (nunca rotulo de fraude/furto/culpa) (RN-06, RN-07).
3. **Atendimento** — chamados anonimizados e enriquecidos, para leitura agregada e
   deteccao antecipada de sinais de ouvidoria (RN-09, RN-10).
4. **Relatorio executivo** — consolida as tres entregas acima para demonstracao.

## Sequencia de prompts

| # | Prompt | Entrega |
|---|---|---|
| 00 | Setup | PRD, catalogos, schemas, volume |
| 01 | Camada bronze | Ingestao fiel do volume, sem regra de negocio |
| 02 | Silver — os numeros | Cadastro limpo, regra dos 3 minutos, dedup e baseline |
| 03 | Silver — o texto | Anonimizacao e enriquecimento das transcricoes |
| 04 | Camada gold | As quatro entregas de negocio e a metric view de DEC/FEC |
| 05 | Dashboard | Painel AI/BI sobre a gold |
| 06 | Agente | Copiloto conversacional em portugues |
| 07 | Relatorio e demonstracao | Relatorio executivo e queries que provam tudo |
