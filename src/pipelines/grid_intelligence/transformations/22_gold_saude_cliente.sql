-- Grao e o CLIENTE, nao a UC -- um cliente pode ter varias UCs, e agrupar por UC esconderia
-- quem ligou uma vez para cada uma (qtd_ucs_com_chamado torna isso visivel). risco_ouvidoria
-- e sinal operacional, nunca acusacao (RN-07). motivo_predominante usa mode(): um relatorio
-- que muda de resposta a cada execucao destroi a confianca do gestor no numero.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.saude_cliente
COMMENT 'Um cliente por linha, com o historico de chamados e um sinal de risco de reclamacao na ouvidoria (alto/medio/baixo). ultima_fala vem do texto ja anonimizado -- quem for atender precisa de contexto, nao do CPF do cliente.'
AS WITH chamado AS (
  SELECT
    a.id_cliente,
    a.id_conjunto,
    a.bairro,
    a.id_uc,
    to_timestamp(concat(a.data_chamado, ' ', a.hora_chamado)) AS momento_chamado,
    a.transcricao_anonimizada,
    e.sentimento,
    e.motivo,
    e.equipamento_citado,
    e.risco_a_saude,
    e.urgencia,
    e.ameacou_ouvidoria
  FROM ${catalogo}.${schema_silver}.chamados_enriquecidos e
  JOIN ${catalogo}.${schema_silver}.chamados_anonimizados a ON a.id_chamado = e.id_chamado
),
por_cliente AS (
  SELECT
    id_cliente,
    mode(id_conjunto)                                AS id_conjunto,
    mode(bairro)                                      AS bairro,
    count(*)                                          AS qtd_chamados,
    count(DISTINCT id_uc)                             AS qtd_ucs_com_chamado,
    count_if(sentimento = 'negative')                 AS qtd_chamados_negativos,
    count_if(ameacou_ouvidoria)                       AS qtd_mencoes_ouvidoria,
    count_if(risco_a_saude)                           AS qtd_chamados_risco_saude,
    count_if(urgencia = 'alta')                       AS qtd_urgencia_alta,
    mode(motivo)                                      AS motivo_predominante,
    max_by(equipamento_citado, momento_chamado)       AS ultimo_equipamento_citado,
    max_by(transcricao_anonimizada, momento_chamado)  AS ultima_fala,
    min(momento_chamado)                              AS primeiro_chamado_em,
    max(momento_chamado)                              AS ultimo_chamado_em
  FROM chamado
  GROUP BY id_cliente
)
SELECT
  p.id_cliente,
  p.id_conjunto,
  u.nome_conjunto,
  p.bairro,
  p.qtd_chamados,
  p.qtd_ucs_com_chamado,
  p.qtd_chamados_negativos,
  round(p.qtd_chamados_negativos / p.qtd_chamados, 2) AS proporcao_negativa,
  p.qtd_mencoes_ouvidoria,
  p.qtd_chamados_risco_saude,
  p.qtd_urgencia_alta,
  p.qtd_chamados >= 3 AND datediff(p.ultimo_chamado_em, p.primeiro_chamado_em) <= 30 AS reincidente,
  p.motivo_predominante,
  p.ultimo_equipamento_citado,
  p.ultima_fala,
  p.primeiro_chamado_em,
  p.ultimo_chamado_em,
  CASE
    WHEN p.qtd_mencoes_ouvidoria > 0                                                                                         THEN 'alto'
    WHEN p.qtd_chamados >= 3 AND datediff(p.ultimo_chamado_em, p.primeiro_chamado_em) <= 30 AND p.qtd_chamados_negativos > 0 THEN 'alto'
    WHEN p.qtd_chamados_risco_saude > 0                                                                                      THEN 'medio'
    ELSE 'baixo'
  END AS risco_ouvidoria
FROM por_cliente p
LEFT JOIN (SELECT DISTINCT id_conjunto, nome_conjunto FROM ${catalogo}.${schema_silver}.unidades_consumidoras) u
  ON u.id_conjunto = p.id_conjunto;
