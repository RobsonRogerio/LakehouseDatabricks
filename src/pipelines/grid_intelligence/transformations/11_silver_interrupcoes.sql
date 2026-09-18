-- RN-01: so interrupcao de fornecimento com 3 minutos ou mais entra na apuracao de DEC/FEC.
-- Abaixo disso e o religador atuando -- galho na rede, desarme e religamento automatico em
-- segundos. O consumidor ve a luz piscar; nao e falta de energia. O limiar vem da
-- configuration do pipeline porque a regra e do regulador, nao do engenheiro.
CREATE OR REFRESH STREAMING TABLE ${catalogo}.${schema_silver}.interrupcoes_validas
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT
  *,
  to_date(inicio)                             AS data_evento,
  date_trunc('MONTH', inicio)                 AS mes_apuracao,
  duracao_minutos / 60.0                      AS duracao_horas,
  (duracao_minutos / 60.0) * qtd_ucs_afetadas AS uc_horas_interrompidas,
  causa = 'climatica'                         AS causa_climatica
FROM STREAM(${catalogo}.${schema_bronze}.interrupcoes)
WHERE duracao_minutos >= ${duracao_minima_interrupcao_min};
