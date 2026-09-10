-- Descarta consumo nulo, negativo ou acima do limite fisico da ligacao (definido aqui, por
-- classe de consumo) e deduplica (id_uc, data): o concentrador reenvia leituras e a mesma
-- chave chega duas vezes. Junta o cadastro para que conjunto, bairro e classe ja venham
-- prontos -- as regras de perdas nao tecnicas nao deveriam refazer esse join.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.consumo_diario
AS SELECT
  c.id_uc,
  c.data,
  c.consumo_kwh,
  c.horas_com_leitura,
  c.sinal_violacao_medidor,
  u.id_conjunto,
  u.bairro,
  u.classe_consumo
FROM ${catalogo}.${schema_bronze}.consumo_diario c
JOIN ${catalogo}.${schema_silver}.unidades_consumidoras u ON u.id_uc = c.id_uc
WHERE c.consumo_kwh IS NOT NULL
  AND c.consumo_kwh >= 0
  AND c.consumo_kwh <= CASE u.classe_consumo
        WHEN 'residencial'   THEN 100
        WHEN 'comercial'     THEN 500
        WHEN 'rural'         THEN 150
        WHEN 'poder_publico' THEN 1000
        WHEN 'industrial'    THEN 5000
      END
QUALIFY row_number() OVER (PARTITION BY c.id_uc, c.data ORDER BY c.ingerido_em DESC) = 1;

-- Insumo dos dois eixos da RN-06: variacao da propria UC contra o passado (eixo 1) e
-- variacao do conjunto vizinho no mesmo periodo (eixo 2). Janela ancorada no maior dia do
-- dataset, nunca em current_date() -- o dataset e sintetico e pode ter sido gerado semana
-- passada. Baseline usa os 90 dias imediatamente antes dos ultimos 30, nao o historico
-- inteiro: a carga cresce ~30% ao ano, e comparar contra 4 anos acusaria alta em toda UC.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.baseline_consumo
AS WITH por_uc AS (
  SELECT
    c.id_uc,
    c.id_conjunto,
    avg(consumo_kwh) FILTER (WHERE data > d.ultimo_dia - INTERVAL 30 DAYS)  AS media_recente,
    count(*)         FILTER (WHERE data > d.ultimo_dia - INTERVAL 30 DAYS)  AS dias_recente,
    avg(consumo_kwh) FILTER (WHERE data <= d.ultimo_dia - INTERVAL 30 DAYS
                              AND data > d.ultimo_dia - INTERVAL 120 DAYS)  AS media_baseline,
    count(*)         FILTER (WHERE data <= d.ultimo_dia - INTERVAL 30 DAYS
                              AND data > d.ultimo_dia - INTERVAL 120 DAYS)  AS dias_baseline
  FROM ${catalogo}.${schema_silver}.consumo_diario c,
       (SELECT max(data) AS ultimo_dia FROM ${catalogo}.${schema_silver}.consumo_diario) d
  GROUP BY c.id_uc, c.id_conjunto
),
por_conjunto AS (
  SELECT id_conjunto, avg(media_recente) AS media_recente_conjunto, avg(media_baseline) AS media_baseline_conjunto
  FROM por_uc
  GROUP BY id_conjunto
)
SELECT
  u.id_uc,
  u.id_conjunto,
  u.media_baseline,
  u.media_recente,
  u.dias_baseline,
  u.dias_recente,
  round(100.0 * (u.media_recente - u.media_baseline) / u.media_baseline, 1)             AS variacao_pct_uc,
  c.media_baseline_conjunto,
  c.media_recente_conjunto,
  round(100.0 * (c.media_recente_conjunto - c.media_baseline_conjunto) / c.media_baseline_conjunto, 1) AS variacao_pct_conjunto
FROM por_uc u
JOIN por_conjunto c ON c.id_conjunto = u.id_conjunto;
