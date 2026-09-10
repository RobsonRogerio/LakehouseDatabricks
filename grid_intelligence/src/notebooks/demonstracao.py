# Databricks notebook source
# MAGIC %md
# MAGIC # Demonstracao -- as queries que provam a plataforma
# MAGIC
# MAGIC Uma consulta para cada afirmacao que o projeto faz, com o resultado esperado documentado
# MAGIC ao lado. Roda contra qualquer ambiente (dev ou prod) via os widgets abaixo.

# COMMAND ----------

dbutils.widgets.text("catalogo", "grid_dev")
dbutils.widgets.text("schema_bronze", "bronze")
dbutils.widgets.text("schema_silver", "silver")
dbutils.widgets.text("schema_gold", "gold")

catalogo = dbutils.widgets.get("catalogo")
spark.sql(f"USE CATALOG `{catalogo}`")
schema_bronze = dbutils.widgets.get("schema_bronze")
schema_silver = dbutils.widgets.get("schema_silver")
schema_gold = dbutils.widgets.get("schema_gold")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. RN-01 tem efeito
# MAGIC Interrupcoes abaixo de 3 minutos sao descartadas entre bronze e silver.
# MAGIC **Esperado: bronze 1.383, silver 1.073, ~22,4% descartado.**

# COMMAND ----------

display(spark.sql(f"""
    SELECT
      (SELECT count(*) FROM {schema_bronze}.interrupcoes)          AS bronze_total,
      (SELECT count(*) FROM {schema_silver}.interrupcoes_validas)  AS silver_total,
      round(100.0 * (1 - (SELECT count(*) FROM {schema_silver}.interrupcoes_validas) * 1.0
                           / (SELECT count(*) FROM {schema_bronze}.interrupcoes)), 1) AS pct_descartado
"""))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. A qualidade tem efeito
# MAGIC Consumo nulo, negativo, acima do limite fisico e duplicata sao descartados entre bronze
# MAGIC e silver, cada motivo contado a parte.
# MAGIC **Esperado: bronze 5.854.587, nulo 23.478, negativo 8.799, duplicatas 14.497, silver 5.801.374.**

# COMMAND ----------

display(spark.sql(f"""
    WITH validos AS (
      SELECT c.id_uc, c.data, c.ingerido_em
      FROM {schema_bronze}.consumo_diario c
      JOIN {schema_silver}.unidades_consumidoras u ON u.id_uc = c.id_uc
      WHERE c.consumo_kwh IS NOT NULL AND c.consumo_kwh >= 0
        AND c.consumo_kwh <= CASE u.classe_consumo
              WHEN 'residencial'   THEN 100
              WHEN 'comercial'     THEN 500
              WHEN 'rural'         THEN 150
              WHEN 'poder_publico' THEN 1000
              WHEN 'industrial'    THEN 5000
            END
    )
    SELECT
      (SELECT count(*) FROM {schema_bronze}.consumo_diario)                       AS bronze_total,
      (SELECT count_if(consumo_kwh IS NULL) FROM {schema_bronze}.consumo_diario)  AS descartado_nulo,
      (SELECT count_if(consumo_kwh < 0) FROM {schema_bronze}.consumo_diario)      AS descartado_negativo,
      count(*) - count(DISTINCT id_uc, data)                                      AS duplicatas_removidas,
      (SELECT count(*) FROM {schema_silver}.consumo_diario)                       AS silver_total
    FROM validos
"""))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. RN-04 e real
# MAGIC O DEC da metric view (MEASURE) e o calculo manual a partir dos insumos gravados na gold
# MAGIC tem de bater, conjunto a conjunto, no mes mais recente.
# MAGIC **Esperado: `dec_metric_view` = `dec_calculo_manual` em toda linha.**

# COMMAND ----------

display(spark.sql(f"""
    SELECT
      m.conjunto,
      round(m.dec_metric_view, 6) AS dec_metric_view,
      round(t.uc_horas_interrompidas / t.total_ucs, 6) AS dec_calculo_manual
    FROM (
      SELECT `Conjunto` AS conjunto, MEASURE(`DEC`) AS dec_metric_view
      FROM {schema_gold}.continuidade_metricas
      WHERE `Mes` = (SELECT max(`Mes`) FROM {schema_gold}.continuidade_metricas)
      GROUP BY ALL
    ) m
    JOIN {schema_gold}.continuidade_conjunto_mes t
      ON t.nome_conjunto = m.conjunto
     AND t.mes_apuracao = (SELECT max(mes_apuracao) FROM {schema_gold}.continuidade_conjunto_mes)
    ORDER BY m.conjunto
"""))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Os dois eixos funcionam
# MAGIC UCs em prioridade alta tem de mostrar queda relevante contra o proprio baseline
# MAGIC (`variacao_da_uc`) enquanto o conjunto ficou estavel (`variacao_do_conjunto` perto de zero).
# MAGIC **Esperado: 20 linhas, todas em Jardim Aurora, `variacao_da_uc` <= -20%.**

# COMMAND ----------

display(spark.sql(f"""
    SELECT id_uc, nome_conjunto, bairro, variacao_da_uc, variacao_do_conjunto,
           sinal_violacao_recente, motivo_observado
    FROM {schema_gold}.prioridade_inspecao_uc
    WHERE prioridade_inspecao = 'alta'
    ORDER BY variacao_da_uc ASC
"""))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. A anonimizacao funciona
# MAGIC A mesma transcricao, na bronze (nome/CPF/telefone identificados -- requer estar no grupo
# MAGIC `atendimento`, senao a coluna vem mascarada por RN-10) e na silver (anonimizada por RN-09).
# MAGIC **Esperado: `bronze_transcricao` com nome/CPF/telefone; `silver_transcricao_anonimizada`
# MAGIC com `[MASCARADO]` no lugar.**

# COMMAND ----------

display(spark.sql(f"""
    SELECT b.id_chamado, b.transcricao AS bronze_transcricao,
           a.transcricao_anonimizada AS silver_transcricao_anonimizada
    FROM {schema_bronze}.chamados b
    JOIN {schema_silver}.chamados_anonimizados a ON a.id_chamado = b.id_chamado
    LIMIT 3
"""))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. O evento narrativo esta la
# MAGIC A cascata climatica de 2026-07-30 (3 conjuntos, ~539 UCs) tem de aparecer como um pico
# MAGIC isolado de chamados por hora, comparado a media das mesmas horas em outros dias.
# MAGIC **Esperado: hora 21 muito acima da media -- os chamados chegam logo depois do inicio dos
# MAGIC eventos, as 21:20.**

# COMMAND ----------

display(spark.sql(f"""
    WITH por_hora AS (
      SELECT date(abertura) AS dia, hour(abertura) AS hora, count(*) AS n
      FROM {schema_bronze}.chamados
      GROUP BY date(abertura), hour(abertura)
    ),
    noite_cascata AS (SELECT hora, n FROM por_hora WHERE dia = '2026-07-30'),
    media_outros_dias AS (
      SELECT hora, avg(n) AS media_chamados
      FROM por_hora WHERE dia != '2026-07-30'
      GROUP BY hora
    )
    SELECT coalesce(c.hora, m.hora) AS hora,
           coalesce(c.n, 0) AS chamados_noite_cascata,
           round(coalesce(m.media_chamados, 0), 2) AS media_mesma_hora_outros_dias
    FROM noite_cascata c
    FULL OUTER JOIN media_outros_dias m ON m.hora = c.hora
    ORDER BY hora
"""))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7. A tendencia esta la
# MAGIC Consumo total por ano tem de crescer ~30% ao ano -- so visivel porque o dataset tem
# MAGIC quatro anos.
# MAGIC **Esperado: cada ano ~1,3x o anterior (2022 e 2026 sao anos parciais no dataset).**

# COMMAND ----------

display(spark.sql(f"""
    SELECT year(data) AS ano, round(sum(consumo_kwh), 0) AS consumo_total_kwh
    FROM {schema_silver}.consumo_diario
    GROUP BY year(data)
    ORDER BY ano
"""))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 8. A sazonalidade esta la
# MAGIC Chamados por mes -- dezembro a marco (verao) tem de ficar perto do dobro dos outros
# MAGIC meses. So visivel com o historico completo.
# MAGIC **Esperado: meses 12, 1, 2, 3 nitidamente mais altos que os demais.**

# COMMAND ----------

display(spark.sql(f"""
    SELECT month(data_chamado) AS mes, count(*) AS qtd_chamados
    FROM {schema_silver}.chamados_anonimizados
    GROUP BY month(data_chamado)
    ORDER BY mes
"""))
