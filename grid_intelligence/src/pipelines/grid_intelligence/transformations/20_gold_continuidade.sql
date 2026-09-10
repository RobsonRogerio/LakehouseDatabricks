-- Insumos aditivos de continuidade por conjunto e mes -- nao o indicador em si. Se esta
-- tabela guardasse DEC/FEC calculado e a metric view recalculasse, seriam duas definicoes
-- (RN-04): no dia em que a formula mudar, alguem atualiza uma e esquece a outra. Por isso
-- aqui so ficam os insumos que somam certo em qualquer recorte: horas-UC interrompidas e
-- interrupcoes-UC (numeradores de DEC e FEC) e o total de UCs do conjunto (denominador). A
-- definicao de DEC e FEC vive so em gold.continuidade_metricas.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.continuidade_conjunto_mes
COMMENT 'Um conjunto por mes. Insumos de continuidade de fornecimento -- horas-UC interrompidas, interrupcoes-UC e total de UCs -- consumidos pela metric view continuidade_metricas, unica fonte de DEC e FEC do projeto.'
AS WITH ucs_por_conjunto AS (
  SELECT id_conjunto, any_value(nome_conjunto) AS nome_conjunto, any_value(municipio) AS municipio, count(*) AS total_ucs
  FROM ${catalogo}.${schema_silver}.unidades_consumidoras
  GROUP BY id_conjunto
)
SELECT
  i.id_conjunto,
  c.nome_conjunto,
  c.municipio,
  i.mes_apuracao,
  c.total_ucs,
  sum(i.uc_horas_interrompidas)   AS uc_horas_interrompidas,
  sum(i.qtd_ucs_afetadas)         AS uc_interrupcoes,
  count(*)                        AS qtd_interrupcoes,
  count_if(i.causa_climatica)     AS qtd_interrupcoes_climaticas,
  count_if(i.tipo = 'programada') AS qtd_interrupcoes_programadas,
  max(i.duracao_horas)            AS maior_duracao_horas
FROM ${catalogo}.${schema_silver}.interrupcoes_validas i
JOIN ucs_por_conjunto c ON c.id_conjunto = i.id_conjunto
GROUP BY i.id_conjunto, c.nome_conjunto, c.municipio, i.mes_apuracao, c.total_ucs;
