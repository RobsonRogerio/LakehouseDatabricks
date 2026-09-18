# Prompt 01 — Camada bronze

> **Prompt 2 de 8.** Requer o prompt 00 concluído: schemas, volume e `.llm/prd.md` no lugar.

---

Leia `.llm/prd.md` antes de começar, inclusive a **diretriz de simplicidade**. Agora vamos
construir a **camada bronze** do medalhão da Grid Intelligence.

## O que quero

Um **Lakeflow Declarative Pipeline serverless** que ingere as quatro bases do volume
`raw.landing` para o schema `bronze`, uma tabela por base.

**Um arquivo só:** `src/pipelines/grid_intelligence/transformations/01_bronze.sql`, com as
quatro tabelas. Elas compartilham o mesmo padrão de ingestão, e separar em quatro arquivos
iguais só espalharia a mesma decisão por quatro lugares.

| Origem no volume | Tabela bronze | Linhas esperadas |
|---|---|---|
| `unidades_consumidoras/` | `bronze.unidades_consumidoras` | 4.000 |
| `interrupcoes/` | `bronze.interrupcoes` | 1.383 |
| `consumo_diario/` | `bronze.consumo_diario` | ~5,85 milhões |
| `chamados/` | `bronze.chamados` | 2.801 |

Todas são **streaming table**: ingestão é append de arquivo novo, e é o que o Auto Loader
sabe fazer de forma incremental.

Use **Auto Loader** (`STREAM read_files`) com formato Parquet. Aponte para a **pasta**, não
para o arquivo: hoje cada base ocupa um Parquet só, mas se uma delas precisar ser
particionada amanhã, nada muda no pipeline.

## O formato de cada tabela

Quatro blocos iguais a este, e nada além disso:

```sql
CREATE OR REFRESH STREAMING TABLE ${catalogo}.${schema_bronze}.interrupcoes
AS SELECT
  *,
  _metadata.file_path AS arquivo_origem,
  current_timestamp() AS ingerido_bronze_em
FROM STREAM read_files(
  '${volume_landing}/interrupcoes/',
  format => 'parquet'
);
```

**Sem expectations, sem `CONSTRAINT`, sem `COMMENT`, sem `CLUSTER BY`.** A bronze é
passagem: o que ela precisa fazer é copiar fielmente e dizer de onde veio.

As duas colunas extras são a RN-12: `arquivo_origem` e `ingerido_bronze_em`. As colunas
`origem` e `ingerido_em` que já vêm do dado dizem de que *sistema* ele saiu; estas duas
dizem por onde ele *entrou* aqui.

## A regra que manda neste arquivo: RN-11

**A ingestão não aplica regra de negócio, não filtra e não corrige.**

Consumo negativo, leitura impossível, interrupção de 40 segundos, cadastro com bairro
vazio — tudo entra exatamente como chegou. Filtrar aqui pareceria limpeza; é destruição de
evidência. Quem descarta é a silver, com regra nomeada e visível no `WHERE`.

O `SELECT *` acima não é preguiça: é a RN-11 escrita em código. Qualquer coluna que você
listasse à mão seria uma decisão sobre o que vale a pena guardar — e essa decisão não é da
bronze.

## Parametrização

O pipeline recebe por `configuration`: catálogo, nome de cada schema, caminho do volume e
o limiar de duração mínima de interrupção. **Nenhum nome de catálogo escrito dentro do
SQL** — os arquivos usam `${catalogo}.${schema_bronze}.<tabela>`, e o valor vem do
`databricks.yml`.

## Uma armadilha que quero registrada em comentário

Cada base ocupa um único arquivo, que é sobrescrito quando o dataset é regerado.
`allowOverwrites => true` faz o Auto Loader reprocessar o arquivo trocado, mas **streaming
table é append-only**: as linhas antigas continuam lá e o volume dobra. Deixe isso escrito
no topo do arquivo, junto com a solução — rodar o pipeline com **full refresh** depois de
regerar.

## Se o pipeline falhar com `DELTA_FEATURE_REQUIRES_MANUAL_ENABLEMENT: timestampNtz`

Vai acontecer. Os timestamps do dataset são **sem fuso horário** (`TIMESTAMP_NTZ`), e o
Delta exige habilitar essa feature explicitamente na tabela.

Há duas saídas, e uma delas está errada:

- **Converter para `TIMESTAMP` na ingestão** — assumiria um fuso que o dado não declara.
  Isso é transformação dentro da bronze, exatamente o que a RN-11 proíbe.
- **Habilitar a feature na tabela** — o tipo entra como chegou, e quem decide o fuso é a
  silver, se precisar.

Use a segunda. É a única exceção à regra de não usar `TBLPROPERTIES`:

```sql
CREATE OR REFRESH STREAMING TABLE ${catalogo}.${schema_bronze}.interrupcoes
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT ...
```

## Se a bronze não ingerir nada

Antes de investigar o Auto Loader, confira a precisão dos timestamps do Parquet:

```bash
databricks experimental aitools tools query --profile grid_intelligence \
  "SELECT * FROM parquet.`/Volumes/grid_dev/raw/landing/interrupcoes/` LIMIT 1"
```

Parquet gravado por pandas sem tratamento fica com `timestamp[ns]`, e **o Spark não lê
nanossegundo**. O gerador deste projeto já converte para microssegundo; se o dado veio de
outro lugar, é a primeira coisa a checar — a falha não é óbvia e parece problema de caminho.

## Ao terminar

1. `databricks bundle deploy -t dev --profile grid_intelligence`
2. Rode o pipeline e me mostre o resultado
3. A contagem de linhas de cada tabela bronze
4. **Quanto defeito entrou**, com uma query só — é o que a silver vai ter de resolver:

```sql
SELECT
  count(*)                                                   AS eventos,
  count_if(duracao_minutos < 3)                              AS abaixo_de_3_min,
  round(100.0 * count_if(duracao_minutos < 3) / count(*), 1) AS pct
FROM grid_dev.bronze.interrupcoes
```

Deve voltar **1.383, 310 e 22,4%**. Esses 22,4% são exatamente o que a RN-01 vai descartar
no próximo prompt — e é bom ver o número antes, para reconhecê-lo depois.

## Critério de aceite

- As quatro tabelas bronze existem e têm o volume esperado
- Nenhuma linha foi filtrada, corrigida ou descartada
- Toda tabela tem `arquivo_origem` e `ingerido_bronze_em`
- Nenhum nome de catálogo aparece dentro do SQL
- Cada tabela cabe em uma tela
