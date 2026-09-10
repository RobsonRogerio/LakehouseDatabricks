# Declarative Automation Bundles Project

This project uses Declarative Automation Bundles (DABs) for deployment. Add project-specific instructions below.

## For AI Agents: Use Databricks AI Tools

**BEFORE any other action, read the `databricks-core` skill.**

It sets you up to work with this project reliably: CLI authentication, profile
selection, data discovery, and the bundle deployment workflow. Without it,
results are often slower and less accurate.

If this skill is not available (Databricks AI Tools are not installed), you can install them for your coding agent in seconds:

```bash
databricks aitools install
```

If the CLI is not installed, see: https://docs.databricks.com/dev-tools/cli/install

---

## Project Instructions

Este e o projeto Grid Intelligence — plataforma de dados e IA da Luz do Vale
Distribuidora S.A. **Leia `.llm/prd.md` antes de qualquer mudanca**: dominio, glossario e
as 14 regras de negocio vivem la, e todo o resto do projeto assume esse contexto.

### Convencoes obrigatorias

- **Portugues do Brasil** em todo texto e nome; nomes de entidades, colunas e arquivos
  **sem acentuacao**.
- **Nenhum nome de catalogo fixado em codigo.** Vem de `${var.catalog}` no
  `databricks.yml`. Schema vem de `${resources.schemas.<camada>.name}`. Isso vale para
  SQL de pipeline, tasks de job e datasets de dashboard — nunca escreva `grid_dev` ou
  `grid_intelligence` num arquivo versionado fora do `databricks.yml`.
- **Nenhum nome de modelo de IA fixado no codigo.** Use as funcoes `ai_*` do Databricks
  (`ai_gen`, `ai_mask`, `ai_classify`, ...), nunca chame um endpoint por nome.
- **Perfil da CLI: `grid_intelligence`.** Todo comando leva `--profile grid_intelligence`.
- **RN-07 em qualquer lugar que gere texto** (SQL, prompt de IA, instrucao do Genie,
  relatorio): a saida sobre consumo atipico e sempre "prioridade de inspecao", nunca
  fraude, furto, roubo, irregularidade ou culpado — nem em coluna, nem em valor gravado,
  nem em texto gerado.

### Diretriz de simplicidade

Codigo que ninguem consegue ler na tela em dez segundos nao serve. Sem `expectations` e
sem `CONSTRAINT` (regra de negocio vira `WHERE`). Sem `COMMENT` em bronze e silver — so
gold e a metric view levam descricao, porque sao o que o agente conversacional le
(RN-14). Sem `TBLPROPERTIES`/`CLUSTER BY` a menos que sem eles quebre. Um `SELECT` direto
vence um `WITH` de quatro CTEs — so quebre em CTE quando a query realmente nao couber de
cabeca.

### O medalhao

Quatro camadas, um pipeline so (`resources/grid_pipeline.pipeline.yml`), arquivos
numerados em `src/pipelines/grid_intelligence/transformations/` na ordem
`0x_bronze` → `1x_silver_*` → `2x_gold_*`, para a ordem de leitura acompanhar a ordem de
execucao. `raw` → `bronze`: `SELECT *`, nada de regra (RN-11). `bronze` → `silver`:
qualidade e regra de negocio, com o motivo do descarte em comentario quando nao for
obvio. `silver` → `gold`: as entregas de negocio, sempre com `COMMENT` em linguagem de
negocio.

Limiares de regra de negocio (RN-01, RN-06) vivem em `configuration` no
`grid_pipeline.pipeline.yml`, nunca escritos no meio de uma query.

### Armadilha conhecida: mascara de coluna e o proprio pipeline

`bronze.chamados` tem uma column mask (RN-10, `src/sql/governanca_dado_pessoal.sql`) que
esconde `nome_solicitante`/`telefone_solicitante`/`transcricao` de quem nao esta no grupo
`atendimento`. Isso inclui o **pipeline**, que le como o usuario que o executa. Se esse
usuario nao estiver no grupo, a silver de chamados recebe texto ja mascarado e a
anonimizacao (RN-09) colapsa silenciosamente para `'[MASCARADO]'` em toda linha — sem
erro, sem aviso. Confira o grupo antes de investigar qualquer coisa estranha em
`silver.chamados_anonimizados` ou downstream dela.

### Metric view e tasks de SQL do job

Metric view (`gold.continuidade_metricas`) e Genie space **nao sao dataset de pipeline
nem recurso de bundle** — a metric view e criada por uma task `sql_task` do job
`grid_atualizacao` a partir de `src/sql/metric_view_continuidade.sql`; o Genie space e
aplicado por `scripts/aplicar_genie_space.py`. Ao editar qualquer um dos dois, redeploy o
bundle (ou rode o script) e rode a task/comando de novo — editar so o arquivo local nao
muda o que esta publicado.

`sql_task` de arquivo `$$...$$` (metric view YAML) **nao roda de forma confiavel via
`databricks experimental aitools tools query --file`** — essa ferramenta mal-interpreta
YAML com 2+ itens numa sequencia. Teste esses arquivos rodando a task real
(`databricks bundle run` ou `databricks jobs run-now --json '{"only": [...]}'`), nao a
ferramenta de query ad hoc.

### IA no projeto

`ai_gen` (relatorio executivo) e as funcoes de `13_silver_chamados.sql` (rota regex, sem
IA) sempre levam duas amarras no prompt/regra: usar so numero fornecido (nunca estimar
ou inventar) e nunca escrever fraude/furto/roubo/irregularidade. Ao dar mais contexto
para um `ai_gen`, prefira **totais pre-calculados em Python/SQL** a listas brutas de
itens — um teste real mostrou o modelo tentando filtrar/contar uma lista sozinho e
errando o numero, mesmo com a instrucao explicita de nao estimar.

### Antes de considerar uma mudanca pronta

```bash
databricks bundle validate --profile grid_intelligence
databricks bundle deploy -t dev --profile grid_intelligence
databricks bundle run grid_atualizacao -t dev --profile grid_intelligence
```

Teste toda query nova pela CLI antes de colocar num dataset de dashboard ou numa task de
job — falha descoberta depois que alguem abriu o dashboard ou o Genie e mais cara de
depurar.
