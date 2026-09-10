# Grid Intelligence

Plataforma de dados e IA da **Luz do Vale Distribuidora S.A.**, uma distribuidora de
energia eletrica ficticia regulada pela ANEEL, construida no Databricks como Declarative
Automation Bundle (DAB).

O projeto cobre a cadeia inteira: ingestao (bronze), regras de negocio e qualidade
(silver), as quatro entregas de negocio e a metric view de continuidade (gold), um
dashboard AI/BI, um copiloto conversacional (Genie) e um relatorio executivo gerado por
IA. O contexto completo — dominio, glossario, as 14 regras de negocio e o modelo de
informacao — esta em [`.llm/prd.md`](.llm/prd.md); leia antes de mexer em qualquer coisa.

## Pre-requisitos

- Databricks CLI (`databricks --version`) autenticado — ver a skill `databricks-core` se
  estiver configurando do zero
- Um workspace Databricks (Free Edition serve; o projeto usa serverless em tudo)
- `uv` para dependencias Python locais (`uv sync --dev`)

## Perfil da CLI

Todo comando deste projeto leva `--profile grid_intelligence`:

```bash
databricks bundle validate --profile grid_intelligence
```

## Do zero ao copiloto

### 1. Catalogos (recurso de conta — o bundle nao cria)

Dois catalogos, um por ambiente. E o catalogo que isola dev de prod — os schemas mantem
os nomes exatos `raw`, `bronze`, `silver` e `gold` nos dois lados.

```bash
databricks experimental aitools tools query --profile grid_intelligence \
  "CREATE CATALOG IF NOT EXISTS grid_dev COMMENT 'Catalogo de desenvolvimento da Grid Intelligence'"

databricks experimental aitools tools query --profile grid_intelligence \
  "CREATE CATALOG IF NOT EXISTS grid_intelligence COMMENT 'Catalogo de producao da Grid Intelligence'"
```

Conceda privilegios no seu usuario (necessario se o catalogo for compartilhado com outra
pessoa alem do dono):

```bash
databricks grants update CATALOG grid_dev \
  --json '{"changes":[{"principal":"SEU-EMAIL","add":["ALL_PRIVILEGES"]}]}' \
  --profile grid_intelligence
```

#### ⚠️ Recomecar do zero (destrutivo)

`CASCADE` remove schemas, tabelas, volumes e os arquivos dentro deles, e **nao pergunta
duas vezes**:

```bash
databricks experimental aitools tools query --profile grid_intelligence \
  "DROP CATALOG IF EXISTS grid_dev CASCADE"
```

Confirme sempre antes de rodar — nunca execute sem ter certeza do ambiente (`grid_dev`
vs `grid_intelligence`).

### 2. Deploy do bundle (schemas, volume, pipeline, jobs, dashboard)

```bash
databricks bundle validate --profile grid_intelligence
databricks bundle deploy -t dev --profile grid_intelligence
```

Cria os schemas `raw`, `bronze`, `silver`, `gold`, o volume `raw.landing`, o pipeline
`grid_intelligence`, o job `grid_atualizacao` e o dashboard AI/BI — tudo sem prefixo de
usuario nos schemas (`experimental.skip_name_prefix_for_schema` no `databricks.yml`).

### 3. Subir os dados

Com o volume criado, envie os quatro Parquet (uma pasta por base):

```bash
databricks fs cp -r landing dbfs:/Volumes/grid_dev/raw/landing --overwrite --profile grid_intelligence
```

### 4. Rodar o pipeline e a governanca

```bash
databricks bundle run grid_atualizacao -t dev --profile grid_intelligence
```

Roda, nesta ordem: o pipeline completo (bronze → silver → gold), a mascara de dado
pessoal sobre `bronze.chamados` (precisa rodar **depois** do pipeline, a cada execucao —
um full refresh recria a tabela e derruba a mascara), a metric view de continuidade e o
relatorio executivo.

**Armadilha de permissao:** a mascara de `bronze.chamados` (RN-10) usa
`is_member('atendimento')`. Quem roda o pipeline precisa estar nesse grupo de workspace,
senao a mascara tambem esconde o dado do proprio pipeline — foi exatamente isso que
quebrou a anonimizacao da silver na primeira tentativa deste projeto. Crie o grupo e
adicione seu usuario antes do primeiro `bundle run`:

```bash
databricks groups create --display-name atendimento --profile grid_intelligence
# pegue o id do grupo e do seu usuario (databricks groups list / databricks current-user me)
databricks groups patch <GROUP_ID> --json '{"schemas":["urn:ietf:params:scim:api:messages:2.0:PatchOp"],"Operations":[{"op":"add","path":"members","value":[{"value":"<USER_ID>"}]}]}' --profile grid_intelligence
```

### 5. Aplicar o Genie space

Genie space ainda nao e recurso de bundle — versionado como JSON e aplicado por script:

```bash
python scripts/aplicar_genie_space.py grid_dev --profile grid_intelligence
```

Idempotente: roda de novo a qualquer momento para atualizar instrucoes ou perguntas de
exemplo sem perder o historico do space.

### 6. Publicar o dashboard

O `bundle deploy` cria o dashboard como rascunho; publique para o link ficar visivel:

```bash
databricks lakeview publish <DASHBOARD_ID> --warehouse-id <WAREHOUSE_ID> --profile grid_intelligence
```

## Estrutura de pastas

```
.llm/prd.md                  Dominio, glossario, 14 regras de negocio — leia primeiro
prompts/                     A sequencia de 8 prompts que guiou a construcao do projeto
databricks.yml               Bundle: variaveis catalog/warehouse_id, targets dev/prod
resources/                   Schemas, volume, pipeline, jobs, dashboard — um arquivo por recurso
src/pipelines/.../transformations/
  01_bronze.sql               Ingestao fiel (Auto Loader), sem regra de negocio (RN-11)
  10-12_silver_*.sql          Cadastro limpo, RN-01 (3 min), consumo e baseline
  13_silver_chamados.sql      Anonimizacao (RN-09) e enriquecimento dos chamados
  20-23_gold_*.sql            As quatro entregas de negocio
src/sql/
  governanca_dado_pessoal.sql Column mask sobre bronze.chamados (RN-10), roda via job
  metric_view_continuidade.sql Definicao unica de DEC/FEC (RN-04), roda via job
src/notebooks/
  relatorio_executivo.py      RF-08: relatorio via ai_gen, task final do job
  demonstracao.py             As 8 queries que provam a plataforma
src/dashboards/               Dashboard AI/BI (Lakeview), dataset_catalog/schema por variavel
src/genie/                    Definicao do Genie space (${catalogo} como marcador)
scripts/aplicar_genie_space.py  Cria ou atualiza o Genie space, idempotente
```

## Regras que valem repetir

- **Catalogo isola ambiente, schema nao.** `raw`, `bronze`, `silver`, `gold` tem o mesmo
  nome em dev e prod — o mesmo SQL roda nos dois. Nenhum nome de catalogo ou schema
  aparece literal em codigo; vem de `${var.catalog}` / `${resources.schemas.<camada>.name}`.
- **RN-01** — so interrupcao de 3 minutos ou mais entra em DEC/FEC. A regra vive na
  silver, nunca no relatorio.
- **RN-04** — DEC e FEC tem uma unica definicao, na metric view `gold.continuidade_metricas`.
  Nenhuma tabela gold guarda DEC/FEC calculado, so os insumos aditivos.
- **RN-07** — a saida da deteccao de perdas e **prioridade de inspecao** (alta/media/baixa),
  nunca um rotulo de fraude, furto ou culpa. Vale no codigo, nos prompts de IA e nas
  respostas do agente.
- **RN-09 / RN-10** — duas protecoes que coexistem: a silver anonimiza o texto antes de
  qualquer analise (RN-09); a bronze mascara a origem para quem le direto (RN-10). Quem
  processa a silver precisa estar no grupo `atendimento`, senao as duas regras se
  cancelam em vez de coexistir (ver "Armadilha de permissao" acima).
- **RN-11** — a bronze nao filtra, nao corrige, nao aplica regra de negocio. `SELECT *`
  e a regra escrita em codigo.
- **RN-13** — o agente conversacional e o relatorio executivo leem **so a camada gold**.

## Comandos uteis

```bash
databricks bundle validate --profile grid_intelligence
databricks bundle run grid_atualizacao -t dev --profile grid_intelligence
databricks experimental aitools tools query --profile grid_intelligence "SELECT ..."
uv run pytest
```
