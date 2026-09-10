# Databricks notebook source
# MAGIC %md
# MAGIC # Relatorio executivo (RF-08)
# MAGIC
# MAGIC Responde, para uma regiao e um dia: "Resuma o que aconteceu em {regiao} nas ultimas
# MAGIC 24 horas e diga o que precisa de acao hoje." Le apenas a camada gold (RN-13) -- nenhuma
# MAGIC celula toca bronze ou silver.

# COMMAND ----------

dbutils.widgets.text("catalogo", "grid_dev")
dbutils.widgets.text("schema_gold", "gold")
dbutils.widgets.text("regiao", "Campinas")
dbutils.widgets.dropdown("usar_ia", "true", ["true", "false"])

catalogo = dbutils.widgets.get("catalogo")
schema_gold = dbutils.widgets.get("schema_gold")
regiao = dbutils.widgets.get("regiao")
usar_ia = dbutils.widgets.get("usar_ia") == "true"

spark.sql(f"USE CATALOG `{catalogo}`")
spark.sql(f"USE SCHEMA `{schema_gold}`")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Dia de referencia
# MAGIC
# MAGIC "Ultimas 24 horas" e o ultimo dia com movimento no painel para a regiao -- nunca
# MAGIC `current_date()`. O dataset e sintetico e pode ter sido gerado dias atras.

# COMMAND ----------

dia_referencia_row = spark.sql(f"""
    SELECT max(dia) AS dia
    FROM painel_operacional_dia
    WHERE municipio = '{regiao}'
""").collect()[0]

if dia_referencia_row["dia"] is None:
    raise ValueError(
        f"Nenhum movimento encontrado em painel_operacional_dia para a regiao '{regiao}'. "
        "Confira: (1) o nome bate exatamente com a coluna municipio (sem acento, capitalizacao "
        "exata); (2) o pipeline ja rodou e populou a gold; (3) a regiao existe no cadastro de "
        "unidades consumidoras."
    )

dia_referencia = dia_referencia_row["dia"]
print(f"Dia de referencia: {dia_referencia}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Operacao por conjunto no dia

# COMMAND ----------

operacao_dia_df = spark.sql(f"""
    SELECT nome_conjunto, qtd_interrupcoes, uc_horas_interrompidas, maior_duracao_horas,
           causa_predominante, qtd_chamados, qtd_chamados_negativos, qtd_risco_saude
    FROM painel_operacional_dia
    WHERE municipio = '{regiao}' AND dia = '{dia_referencia}'
    ORDER BY nome_conjunto
""")
display(operacao_dia_df)
operacao_dia = [r.asDict() for r in operacao_dia_df.collect()]

# COMMAND ----------

# MAGIC %md
# MAGIC ## O dia contra a normalidade
# MAGIC
# MAGIC Compara o volume de chamados do dia com a media dos 30 dias anteriores na mesma regiao.

# COMMAND ----------

normalidade_row = spark.sql(f"""
    WITH dia_de_referencia AS (
        SELECT sum(qtd_chamados) AS chamados_hoje
        FROM painel_operacional_dia
        WHERE municipio = '{regiao}' AND dia = '{dia_referencia}'
    ),
    ultimos_30_dias AS (
        SELECT dia, sum(qtd_chamados) AS chamados_dia
        FROM painel_operacional_dia
        WHERE municipio = '{regiao}'
          AND dia BETWEEN date_sub('{dia_referencia}', 30) AND date_sub('{dia_referencia}', 1)
        GROUP BY dia
    )
    SELECT
        (SELECT chamados_hoje FROM dia_de_referencia)      AS chamados_hoje,
        round(avg(chamados_dia), 1)                        AS media_chamados_30_dias
    FROM ultimos_30_dias
""").collect()[0]

chamados_hoje = normalidade_row["chamados_hoje"] or 0
media_chamados_30_dias = normalidade_row["media_chamados_30_dias"] or 0.0
print(f"Chamados hoje: {chamados_hoje} | media dos 30 dias anteriores: {media_chamados_30_dias}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Continuidade do mes (metric view, RN-04)

# COMMAND ----------

continuidade_row = spark.sql(f"""
    SELECT MEASURE(`DEC`) AS dec_mes, MEASURE(`FEC`) AS fec_mes
    FROM continuidade_metricas
    WHERE `Municipio` = '{regiao}' AND `Mes` = (SELECT max(`Mes`) FROM continuidade_metricas)
    GROUP BY ALL
""").collect()[0]

dec_mes = round(continuidade_row["dec_mes"], 2) if continuidade_row["dec_mes"] is not None else None
fec_mes = round(continuidade_row["fec_mes"], 2) if continuidade_row["fec_mes"] is not None else None
print(f"DEC do mes: {dec_mes} h | FEC do mes: {fec_mes}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## O que precisa de acao hoje
# MAGIC
# MAGIC Bairros com UCs em prioridade alta e clientes em risco de ouvidoria, restritos aos
# MAGIC conjuntos da regiao pedida -- prioridade_inspecao_uc e saude_cliente nao tem coluna de
# MAGIC municipio, entao o filtro passa pelos conjuntos da regiao (ambos gold, RN-13 preservada).

# COMMAND ----------

bairros_prioridade_df = spark.sql(f"""
    SELECT bairro, count(*) AS qtd_ucs
    FROM prioridade_inspecao_uc
    WHERE prioridade_inspecao = 'alta'
      AND nome_conjunto IN (SELECT DISTINCT nome_conjunto FROM painel_operacional_dia WHERE municipio = '{regiao}')
    GROUP BY bairro
    ORDER BY qtd_ucs DESC
""")
display(bairros_prioridade_df)
bairros_prioridade = [r.asDict() for r in bairros_prioridade_df.collect()]

clientes_ouvidoria_df = spark.sql(f"""
    SELECT id_cliente, bairro, qtd_chamados, motivo_predominante
    FROM saude_cliente
    WHERE risco_ouvidoria = 'alto'
      AND nome_conjunto IN (SELECT DISTINCT nome_conjunto FROM painel_operacional_dia WHERE municipio = '{regiao}')
    ORDER BY qtd_chamados DESC
""")
display(clientes_ouvidoria_df)
clientes_ouvidoria = [r.asDict() for r in clientes_ouvidoria_df.collect()]

# COMMAND ----------

# MAGIC %md
# MAGIC ## Texto final
# MAGIC
# MAGIC Com IA (`usar_ia = "true"`): `ai_gen` com duas amarras explicitas no prompt -- usar so os
# MAGIC numeros fornecidos, e nunca escrever fraude/furto/roubo/irregularidade (RN-07). Sem IA
# MAGIC (`usar_ia = "false"`, RF-09): mesmo fato, montado por gabarito -- muda a prosa, nao o
# MAGIC numero.

# COMMAND ----------

def montar_fatos_texto():
    linhas_conjuntos = "\n".join(
        f"- {c['nome_conjunto']}: {c['qtd_interrupcoes']} interrupcoes, "
        f"{round(c['uc_horas_interrompidas'], 1)} horas-UC interrompidas "
        f"(maior evento {round(c['maior_duracao_horas'], 1)}h, causa predominante "
        f"{c['causa_predominante'] or 'sem interrupcao'}), {c['qtd_chamados']} chamados "
        f"({c['qtd_chamados_negativos']} negativos, {c['qtd_risco_saude']} com risco a saude)"
        for c in operacao_dia
    ) or "- Nenhum conjunto com movimento registrado no dia."

    # Listas truncadas a uma amostra, com o TOTAL calculado aqui em Python (nunca pelo
    # modelo) -- um teste anterior mostrou o ai_gen tentando filtrar/contar itens da lista
    # sozinho e errando o numero. Menos material bruto, menos chance de conta por conta
    # propria: so entregamos agregados prontos.
    total_ucs_prioridade_alta = sum(b["qtd_ucs"] for b in bairros_prioridade)
    amostra_bairros = "\n".join(
        f"- {b['bairro']}: {b['qtd_ucs']} UCs" for b in bairros_prioridade[:5]
    ) or "- Nenhum bairro com UC em prioridade alta."
    if len(bairros_prioridade) > 5:
        amostra_bairros += f"\n- (mais {len(bairros_prioridade) - 5} bairros na lista completa)"

    total_clientes_ouvidoria = len(clientes_ouvidoria)
    amostra_clientes = "\n".join(
        f"- {c['id_cliente']} ({c['bairro']}): {c['qtd_chamados']} chamados, motivo predominante {c['motivo_predominante']}"
        for c in clientes_ouvidoria[:5]
    ) or "- Nenhum cliente em risco alto de ouvidoria."
    if len(clientes_ouvidoria) > 5:
        amostra_clientes += f"\n- (mais {len(clientes_ouvidoria) - 5} clientes na lista completa)"

    return linhas_conjuntos, total_ucs_prioridade_alta, amostra_bairros, total_clientes_ouvidoria, amostra_clientes


linhas_conjuntos, total_ucs_prioridade_alta, amostra_bairros, total_clientes_ouvidoria, amostra_clientes = montar_fatos_texto()

fatos = f"""
Regiao: {regiao}
Dia de referencia: {dia_referencia}

Operacao por conjunto no dia:
{linhas_conjuntos}

Chamados hoje: {chamados_hoje} (media dos 30 dias anteriores: {media_chamados_30_dias})

Continuidade do mes (metric view): DEC {dec_mes} horas, FEC {fec_mes}

Total de UCs em prioridade alta de inspecao: {total_ucs_prioridade_alta}
Amostra de bairros com UCs em prioridade alta (use so o total acima para quantificar, esta
lista e so exemplo de onde ficam):
{amostra_bairros}

Total de clientes em risco alto de reclamacao na ouvidoria: {total_clientes_ouvidoria}
Amostra de clientes em risco alto (use so o total acima para quantificar, esta lista e so
exemplo de quem sao):
{amostra_clientes}
""".strip()

print(fatos)

# COMMAND ----------

if usar_ia:
    prompt = f"""Voce e um analista da Luz do Vale Distribuidora S.A. escrevendo um relatorio
executivo curto para a diretoria, a partir exclusivamente dos fatos abaixo.

REGRAS OBRIGATORIAS:
1. Use exclusivamente os numeros fornecidos nos fatos abaixo. Nunca estime, nunca arredonde
   para efeito de retorica, nunca invente valor que nao esteja explicito nos fatos. As
   "amostras" de bairros e clientes sao so exemplos ilustrativos -- NUNCA conte, filtre ou
   some itens delas para gerar um numero novo; para quantificar, use exclusivamente os
   totais ja calculados ("Total de UCs em prioridade alta" e "Total de clientes em risco
   alto") fornecidos prontos acima.
2. UCs com consumo atipico sao PRIORIDADE DE INSPECAO, nunca escreva as palavras fraude,
   furto, roubo ou irregularidade em nenhuma hipotese.

Estrutura em tres partes, nesta ordem: (1) o que aconteceu, (2) impacto em numeros, (3) o que
precisa de acao. Tom direto, sem adjetivo de marketing -- quem le tem dois minutos. Maximo de
250 palavras. Responda em portugues do Brasil.

FATOS:
{fatos}
"""
    texto_final = spark.sql("SELECT ai_gen(:prompt) AS texto", args={"prompt": prompt}).collect()[0]["texto"]
else:
    partes = [f"O que aconteceu em {regiao} em {dia_referencia}:", linhas_conjuntos]
    if chamados_hoje > media_chamados_30_dias * 1.2:
        partes.append(f"\nVolume de chamados acima do normal: {chamados_hoje} hoje contra media de {media_chamados_30_dias} nos 30 dias anteriores.")
    elif chamados_hoje < media_chamados_30_dias * 0.8:
        partes.append(f"\nVolume de chamados abaixo do normal: {chamados_hoje} hoje contra media de {media_chamados_30_dias} nos 30 dias anteriores.")
    else:
        partes.append(f"\nVolume de chamados dentro do normal: {chamados_hoje} hoje, media de {media_chamados_30_dias} nos 30 dias anteriores.")
    partes.append(f"\nImpacto em numeros: DEC do mes {dec_mes} horas, FEC {fec_mes}.")
    partes.append(
        "\nO que precisa de acao hoje (prioridade de inspecao tecnica, nao acusacao): "
        f"{total_ucs_prioridade_alta} UCs em prioridade alta e {total_clientes_ouvidoria} "
        "clientes em risco alto de ouvidoria. Amostra de bairros:"
    )
    partes.append(amostra_bairros)
    partes.append("Amostra de clientes:")
    partes.append(amostra_clientes)
    texto_final = "\n".join(partes)

print("\n" + "=" * 80)
print(texto_final)
print("=" * 80)

# COMMAND ----------

dbutils.notebook.exit(texto_final)
