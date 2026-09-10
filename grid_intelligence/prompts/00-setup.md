# Prompt 00 — Setup e planejamento

> **Como usar:** cole este texto inteiro no Claude Code, dentro do repositório do projeto.
> Ele é o primeiro de uma sequência de **8 prompts**. Cada um entrega uma feature completa,
> com deploy e resultado visível. Não pule a ordem: cada prompt assume o anterior pronto.

---

Você vai me ajudar a construir a plataforma de dados e IA de uma distribuidora de energia
elétrica fictícia, a **Luz do Vale Distribuidora S.A.**, no Databricks. O projeto se chama
**Grid Intelligence**.

Este é o **prompt 1 de 8**. Neste primeiro, quero apenas o alicerce: entender o domínio,
registrar as regras de negócio e criar a infraestrutura. Não construa transformação,
dashboard nem agente agora — cada um tem o seu prompt.

## Contexto de negócio

Uma distribuidora de energia opera sob regulação da ANEEL e tem três dores simultâneas,
todas mensuráveis em dinheiro:

1. **Continuidade do fornecimento.** Interromper além do limite regulatório gera
   compensação financeira automática ao consumidor. Em 2024 as distribuidoras brasileiras
   pagaram mais de R$ 1,1 bilhão em compensações.
2. **Perdas não técnicas.** Energia distribuída e não faturada — furto, fraude e erro de
   medição. Em 2025 somaram ~R$ 11,5 bilhões, dos quais ~R$ 7,9 bilhões foram repassados
   à tarifa.
3. **Atendimento ao cliente.** Milhares de ligações viram transcrição e ninguém lê. Dentro
   delas está o aviso antecipado da reclamação na ouvidoria.

## Glossário — use estes termos, sem sinônimo aproximado

| Termo | Definição |
|---|---|
| **UC — Unidade Consumidora** | O ponto de entrega de energia. **Não é sinônimo de cliente**: um cliente pode ter várias UCs |
| **Conjunto** | Subdivisão geográfica da área de concessão. É a unidade de agregação do regulador |
| **DEC** | Duração Equivalente de Interrupção por UC — tempo médio, em horas, sem fornecimento |
| **FEC** | Frequência Equivalente de Interrupção por UC — número médio de interrupções |
| **PNT** | Perdas Não Técnicas |
| **Prioridade de inspeção** | Classificação de quanto uma UC merece visita técnica |

## Regras de negócio que valem para o projeto inteiro

- **RN-01** — Só interrupções com **3 minutos ou mais** entram na apuração de DEC e FEC.
  A regra vive na camada de transformação, nunca no relatório.
- **RN-04** — DEC e FEC têm **uma única definição** no sistema, consumida por dashboard,
  agente e relatório.
- **RN-06** — Uma UC é candidata a inspeção quando o consumo cai em **dois eixos
  simultâneos**: contra o próprio baseline **e** enquanto a vizinhança permanece estável.
  Só o primeiro eixo apontaria o bairro inteiro depois de um apagão.
- **RN-07** — A saída da detecção é **prioridade de inspeção** — alta, média, baixa.
  **Nunca** um rótulo de fraude, furto ou culpa. Queda de consumo também é mudança de
  morador, imóvel desocupado, defeito de medidor e erro de leitura. Em setor regulado a
  diferença é jurídica. Nenhuma coluna, variável ou comentário do projeto pode usar as
  palavras "fraude", "furto" ou "culpado" como rótulo de saída.
- **RN-09** — Dado pessoal em transcrição é **mascarado antes** de qualquer análise de
  conteúdo.
- **RN-10** — O texto original identificado é preservado com **acesso restrito**. Duas
  proteções que coexistem: uma na leitura, outra na análise.
- **RN-11** — A camada de ingestão **não filtra, não corrige e não aplica regra de
  negócio**. Leitura inválida de medidor é um fato sobre o medidor. Filtrar na ingestão
  parece limpeza; é destruição de evidência.
- **RN-12** — Todo registro ingerido carrega origem e momento de ingestão.
- **RN-13** — O agente conversacional acessa **apenas a camada de negócio**.
- **RN-14** — As entidades da **camada gold** carregam descrição em linguagem de negócio —
  é o que o agente lê. Bronze e silver não precisam: são passagem.

## Diretriz de simplicidade — vale para todos os 8 prompts

Este projeto é construído **ao vivo, em aula**. Código que ninguém consegue ler na tela em
dez segundos não serve, mesmo que seja mais robusto.

**Escreva o mínimo que faz a coisa funcionar:**

- **Sem expectations e sem `CONSTRAINT`** nas tabelas. Regra de negócio vira `WHERE`, que
  qualquer pessoa lê sem precisar saber o que é `ON VIOLATION`.
- **Sem `COMMENT` em bronze e silver.** Elas são passagem. Só a **gold** e a **metric view**
  levam descrição — são o que o agente conversacional lê, e ali a curadoria é o produto
  (RN-14).
- **Sem `TBLPROPERTIES`, `CLUSTER BY` e afins**, a menos que sem eles quebre.
- **Sem tratamento de caso que o dataset não tem.** Não invente defesa para dado que não
  existe.
- **Um `SELECT` direto vence um `WITH` de quatro CTEs.** Só quebre em CTE quando a query
  realmente não couber de cabeça.

Comentário no código só onde a decisão **não é óbvia pelo código** — a regra dos 3 minutos
merece duas linhas explicando por quê; um `CAST` não merece nenhuma.

Se em algum momento você achar que o certo é acrescentar validação, **não acrescente**: me
diga em uma linha o que faria, e eu decido.

## Convenções obrigatórias

- Todo texto e todo nome em **português do Brasil**; nomes de entidades, colunas e
  arquivos **sem acentuação**.
- **Nenhum nome de catálogo fixado em código.** Catálogo vem de `${var.catalog}` no
  `databricks.yml`; schema vem de `${resources.schemas.<camada>.name}`.
- **Nenhum nome de modelo de IA fixado no código.** Use as funções `ai_*` do Databricks.
- Perfil da CLI: `grid_intelligence`. Todo comando leva `--profile grid_intelligence`.

## Os dados

Quatro bases sintéticas, já geradas, em Parquet:

| Base | Grão | Volume |
|---|---|---|
| `unidades_consumidoras` | uma por ponto de entrega | 4.000 |
| `interrupcoes` | uma por evento de rede | 1.383 |
| `consumo_diario` | uma por UC por dia | **~5,85 milhões** (4 anos) |
| `chamados` | uma por ligação, com transcrição | 2.801 |

O dataset tem **quatro anos de histórico**, crescimento de **30% ao ano** na carga e
**sazonalidade de verão** no atendimento (dezembro a março recebem quase o dobro de
ligações). Ele carrega **defeitos propositais** — consumo nulo, negativo, fisicamente
impossível, linhas duplicadas e interrupções abaixo de 3 minutos. Não são bug: existem
para as validações de qualidade e a RN-01 terem o que fazer.

## O que fazer agora

1. **Leia a skill `databricks-core`** antes de qualquer comando, e depois a
   `databricks-dabs`.
2. Escreva **`.llm/prd.md`** com o contexto acima: domínio, glossário, regras de negócio,
   modelo de informação e as quatro entregas de negócio previstas. É o documento que todos
   os prompts seguintes vão consultar.
3. **Crie os catálogos** (ver abaixo).
4. Crie no bundle os **schemas** `raw`, `bronze`, `silver` e `gold`, e o **volume**
   `raw.landing`. Um schema por camada — o nome do schema já é a camada, então as tabelas
   dentro dele não repetem o prefixo (`bronze.chamados`, nunca `bronze_chamados`).
5. Configure `dev` e `prod` isolados **por catálogo**, não por nome de schema.
6. Rode `databricks bundle validate` e `databricks bundle deploy -t dev`.
7. Me diga exatamente **onde subir os arquivos de dados**, com o caminho completo.

## Os catálogos

Dois catálogos, um por ambiente. É o catálogo que isola dev de produção — os schemas mantêm os
nomes exatos `raw`, `bronze`, `silver` e `gold` nos dois lados, para que o mesmo SQL rode em
qualquer ambiente sem uma linha diferente.

| Ambiente | Catálogo | Quem usa |
|---|---|---|
| `dev` | `grid_dev` | você, no dia a dia |
| `prod` | `grid_intelligence` | o ambiente final, depois de validado em dev |

**Catálogo é a única coisa que o bundle não cria** — é recurso de conta, e o deploy assume que já
existe. Schemas e volume ficam no bundle; catálogo, não.

Crie os dois **por SQL**, e não com `databricks catalogs create`:

```bash
databricks experimental aitools tools query --profile grid_intelligence \
  "CREATE CATALOG IF NOT EXISTS grid_dev COMMENT 'Catalogo de desenvolvimento da Grid Intelligence'"

databricks experimental aitools tools query --profile grid_intelligence \
  "CREATE CATALOG IF NOT EXISTS grid_intelligence COMMENT 'Catalogo de producao da Grid Intelligence'"

databricks catalogs list --profile grid_intelligence
```

**Por que SQL e não `catalogs create`:** em qualquer conta com Default Storage ligado — o caso da
Free Edition — a API por trás do comando exige um `storage_root` explícito e devolve
`Metastore storage root URL does not exist`. O `CREATE CATALOG` por SQL usa o armazenamento padrão
da conta e passa. Se até ele reclamar, me avise: aí o caminho é a interface, em Catalog → Create
catalog.

Depois, conceda permissão ao meu usuário nos dois catálogos:

```bash
databricks grants update CATALOG grid_dev \
  --json '{"changes":[{"principal":"SEU-EMAIL","add":["ALL_PRIVILEGES"]}]}' \
  --profile grid_intelligence
```

Catálogo sem *grant* é catálogo inútil: o pipeline falha depois com
`user does not have permission to CREATE SCHEMA`.

### Recomeçar do zero

Se um catálogo já existir e eu quiser recomeçar limpo, o comando é destrutivo e **não pergunta
duas vezes** — `CASCADE` remove schemas, tabelas, volumes e os arquivos dentro deles:

```bash
databricks experimental aitools tools query --profile grid_intelligence \
  "DROP CATALOG IF EXISTS grid_dev CASCADE"
```

**Sempre confirme comigo antes de rodar isso.** Deixe o comando registrado no README, na seção de
setup, com o aviso de que é destrutivo.

## Os schemas e o volume, no bundle

Declare em `resources/grid_schemas.yml`:

- os schemas `raw`, `bronze`, `silver` e `gold`
- o volume **managed** `landing`, dentro de `raw`

Nomes de schema vêm de `${resources.schemas.<camada>.name}` onde forem referenciados; o catálogo
vem de `${var.catalog}`. **Nenhum dos dois escrito literalmente em qualquer arquivo.**

Adicione `experimental.skip_name_prefix_for_schema: true` ao `databricks.yml`. Sem isso, em
`mode: development` o bundle prefixa os schemas com meu nome de usuário e `bronze` vira
`meunome_bronze` — o isolamento entre ambientes é feito pelo catálogo, não pelo nome do schema.

Depois: `databricks bundle validate` e `databricks bundle deploy -t dev`.

## Onde vou subir os dados

Com o volume criado pelo deploy, me diga o caminho completo de cada base, no formato que eu possa
colar direto na interface de upload:

```
/Volumes/grid_dev/raw/landing/unidades_consumidoras/
/Volumes/grid_dev/raw/landing/interrupcoes/
/Volumes/grid_dev/raw/landing/consumo_diario/
/Volumes/grid_dev/raw/landing/chamados/
```

E me dê também o comando de subir tudo de uma vez pelo terminal, lembrando que **o caminho de
origem é o da minha máquina** — confira onde os Parquet estão antes de montar o comando:

```bash
databricks fs cp -r <PASTA_LOCAL> dbfs:/Volumes/grid_dev/raw/landing \
  --overwrite --profile grid_intelligence
```

O prefixo `dbfs:` é obrigatório mesmo para Volume do Unity Catalog.

Uma pasta por base, com um único arquivo Parquet dentro — inclusive a de consumo diário, com 5,85
milhões de linhas. É a pasta, e não o arquivo, que é o contrato com a camada bronze: se um dia uma
base precisar ser particionada, o pipeline não muda.

## Critério de aceite

- Os dois catálogos existem e eu tenho `ALL PRIVILEGES` nos dois
- O comando de derrubar o catálogo está documentado no README, com o aviso de que é destrutivo
- `databricks bundle validate --profile grid_intelligence` passa sem erro
- `databricks bundle deploy -t dev` cria os quatro schemas e o volume `raw.landing`
- Os schemas **não** têm meu nome de usuário como prefixo
- Nenhum nome de catálogo ou schema aparece escrito literalmente no código
- Recebi os quatro caminhos de upload e o comando de `fs cp`
- `.llm/prd.md` existe e contém o glossário e as 14 regras de negócio

## O que vem depois

Não faça nada disso agora — cada item é um prompt próprio:

| # | Prompt | Entrega |
|---|---|---|
| 01 | Camada bronze | Ingestão fiel do volume, sem regra de negócio |
| 02 | Silver — os números | Cadastro limpo, a regra dos 3 minutos, dedup e baseline |
| 03 | Silver — o texto | Anonimização e enriquecimento das transcrições — com IA ou por regex |
| 04 | Camada gold | As quatro entregas de negócio e a metric view de DEC/FEC |
| 05 | Dashboard | Painel AI/BI sobre a gold |
| 06 | Agente | Copiloto conversacional em português |
| 07 | Relatório e demonstração | Relatório executivo e as queries que provam tudo |

Quando terminar o setup, me diga o que criou e pare. Eu envio o próximo.
