-- Unica tabela gold que le outra tabela gold (prioridade_inspecao_uc) -- o prefixo numerico
-- dos arquivos existe para deixar essa ordem legivel.
--
-- Agrega interrupcao e chamado SEPARADAMENTE e une com FULL OUTER JOIN, em vez de um join
-- unico das bases: dia com interrupcao e sem chamado existe, dia com chamado e sem
-- interrupcao tambem. Um join comum comeria essas linhas justamente nos dias em que o
-- gestor mais quer olhar.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.painel_operacional_dia
COMMENT 'Um conjunto por dia: interrupcoes, chamados e sinais de medidor do dia, mais o backlog de inspecao pendente do conjunto. acao_recomendada ordena o que olhar primeiro -- risco a saude, depois ameaca de ouvidoria, depois impacto de rede, depois inspecao.'
AS WITH interrupcao_dia AS (
  SELECT
    id_conjunto,
    data_evento                     AS dia,
    count(*)                        AS qtd_interrupcoes,
    sum(uc_horas_interrompidas)     AS uc_horas_interrompidas,
    max(duracao_horas)              AS maior_duracao_horas,
    mode(causa)                     AS causa_predominante
  FROM ${catalogo}.${schema_silver}.interrupcoes_validas
  GROUP BY id_conjunto, data_evento
),
chamado_dia AS (
  SELECT
    a.id_conjunto,
    a.data_chamado                  AS dia,
    count(*)                        AS qtd_chamados,
    count_if(e.sentimento = 'negative')    AS qtd_chamados_negativos,
    count_if(e.risco_a_saude)              AS qtd_risco_saude,
    count_if(e.ameacou_ouvidoria)          AS qtd_ameacaram_ouvidoria,
    count_if(e.urgencia = 'alta')          AS qtd_urgencia_alta
  FROM ${catalogo}.${schema_silver}.chamados_anonimizados a
  JOIN ${catalogo}.${schema_silver}.chamados_enriquecidos e ON e.id_chamado = a.id_chamado
  GROUP BY a.id_conjunto, a.data_chamado
),
sinal_medidor_dia AS (
  SELECT id_conjunto, data AS dia, count_if(sinal_violacao_medidor) AS qtd_sinais_violacao_medidor
  FROM ${catalogo}.${schema_silver}.consumo_diario
  GROUP BY id_conjunto, data
),
backlog_inspecao AS (
  SELECT id_conjunto, count_if(prioridade_inspecao = 'alta') AS ucs_prioridade_alta, count_if(prioridade_inspecao = 'media') AS ucs_prioridade_media
  FROM ${catalogo}.${schema_gold}.prioridade_inspecao_uc
  GROUP BY id_conjunto
),
conjunto AS (
  SELECT DISTINCT id_conjunto, nome_conjunto, municipio FROM ${catalogo}.${schema_silver}.unidades_consumidoras
)
SELECT
  c.nome_conjunto,
  c.municipio,
  coalesce(i.id_conjunto, ch.id_conjunto)  AS id_conjunto,
  coalesce(i.dia, ch.dia)                  AS dia,
  coalesce(i.qtd_interrupcoes, 0)          AS qtd_interrupcoes,
  coalesce(i.uc_horas_interrompidas, 0.0)  AS uc_horas_interrompidas,
  coalesce(i.maior_duracao_horas, 0.0)     AS maior_duracao_horas,
  i.causa_predominante,
  coalesce(ch.qtd_chamados, 0)             AS qtd_chamados,
  coalesce(ch.qtd_chamados_negativos, 0)   AS qtd_chamados_negativos,
  coalesce(ch.qtd_risco_saude, 0)          AS qtd_risco_saude,
  coalesce(ch.qtd_ameacaram_ouvidoria, 0)  AS qtd_ameacaram_ouvidoria,
  coalesce(ch.qtd_urgencia_alta, 0)        AS qtd_urgencia_alta,
  coalesce(s.qtd_sinais_violacao_medidor, 0) AS qtd_sinais_violacao_medidor,
  coalesce(b.ucs_prioridade_alta, 0)       AS ucs_prioridade_alta,
  coalesce(b.ucs_prioridade_media, 0)      AS ucs_prioridade_media,
  CASE
    WHEN coalesce(ch.qtd_risco_saude, 0) > 0         THEN 'atender chamado de risco a saude hoje'
    WHEN coalesce(ch.qtd_ameacaram_ouvidoria, 0) > 0 THEN 'contatar cliente antes da reclamacao virar ouvidoria'
    WHEN coalesce(i.uc_horas_interrompidas, 0) > 0   THEN 'investigar impacto de rede do dia'
    WHEN coalesce(b.ucs_prioridade_alta, 0) > 0      THEN 'programar inspecao das UCs de prioridade alta'
    ELSE 'sem acao pendente'
  END AS acao_recomendada
FROM interrupcao_dia i
FULL OUTER JOIN chamado_dia ch ON ch.id_conjunto = i.id_conjunto AND ch.dia = i.dia
LEFT JOIN sinal_medidor_dia s ON s.id_conjunto = coalesce(i.id_conjunto, ch.id_conjunto) AND s.dia = coalesce(i.dia, ch.dia)
LEFT JOIN backlog_inspecao b ON b.id_conjunto = coalesce(i.id_conjunto, ch.id_conjunto)
JOIN conjunto c ON c.id_conjunto = coalesce(i.id_conjunto, ch.id_conjunto);
