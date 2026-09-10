-- RN-06: uma UC entra aqui quando cai contra o proprio baseline (eixo 1) OU mostra sinal de
-- violacao recente no medidor -- a combinacao dos dois eixos e o que separa "queda
-- individual" de "evento de rede" (todo o conjunto caindo junto). silver.baseline_consumo ja
-- traz as duas janelas comparaveis prontas do prompt 02: nada aqui recalcula media.
--
-- RN-07: a saida e prioridade de inspecao, nunca acusacao. motivo_observado descreve o que
-- foi visto no dado, nao uma causa -- queda de consumo tambem e mudanca de morador, imovel
-- desocupado, defeito de medidor ou erro de leitura.
--
-- RN-08: regra explicavel, nao modelo treinado -- nao existe rotulo confiavel de
-- irregularidade neste dataset, e qualquer pessoa precisa reconstruir, linha a linha, por
-- que uma UC entrou na lista.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_gold}.prioridade_inspecao_uc
COMMENT 'UCs candidatas a inspecao tecnica, uma por linha. Prioridade (alta/media/baixa) por queda de consumo em dois eixos simultaneos -- contra o proprio historico e com a vizinhanca estavel -- mais o sinal de violacao no medidor. Nunca um rotulo de fraude, furto ou culpa (RN-07): quem decide o proximo passo e o inspetor.'
AS WITH sinal_recente AS (
  SELECT id_uc, bool_or(sinal_violacao_medidor) AS sinal_violacao_recente
  FROM ${catalogo}.${schema_silver}.consumo_diario
  WHERE data > (SELECT max(data) - INTERVAL 30 DAYS FROM ${catalogo}.${schema_silver}.consumo_diario)
  GROUP BY id_uc
),
avaliado AS (
  SELECT
    b.id_uc,
    b.id_conjunto,
    u.nome_conjunto,
    u.bairro,
    u.classe_consumo,
    b.variacao_pct_uc                                                              AS variacao_da_uc,
    b.variacao_pct_conjunto                                                        AS variacao_do_conjunto,
    b.media_baseline                                                               AS consumo_medio_baseline_kwh,
    b.media_recente                                                                AS consumo_medio_recente_kwh,
    b.dias_baseline                                                                AS dias_no_baseline,
    b.dias_recente                                                                 AS dias_no_periodo_recente,
    b.variacao_pct_uc <= ${limiar_queda_uc_pct}                                    AS caiu_contra_si,
    abs(b.variacao_pct_conjunto) <= ${faixa_estabilidade_conjunto_pct}             AS vizinhanca_estavel,
    coalesce(s.sinal_violacao_recente, false)                                      AS sinal_violacao_recente
  FROM ${catalogo}.${schema_silver}.baseline_consumo b
  JOIN ${catalogo}.${schema_silver}.unidades_consumidoras u ON u.id_uc = b.id_uc
  LEFT JOIN sinal_recente s ON s.id_uc = b.id_uc
)
SELECT
  id_uc,
  id_conjunto,
  nome_conjunto,
  bairro,
  classe_consumo,
  caiu_contra_si AND vizinhanca_estavel AS atende_os_dois_eixos,
  caiu_contra_si,
  vizinhanca_estavel,
  sinal_violacao_recente,
  variacao_da_uc,
  variacao_do_conjunto,
  consumo_medio_baseline_kwh,
  consumo_medio_recente_kwh,
  dias_no_baseline,
  dias_no_periodo_recente,
  CASE
    WHEN caiu_contra_si AND vizinhanca_estavel AND sinal_violacao_recente THEN 'alta'
    WHEN caiu_contra_si AND vizinhanca_estavel                            THEN 'media'
    WHEN sinal_violacao_recente                                          THEN 'media'
    ELSE 'baixa'
  END AS prioridade_inspecao,
  CASE
    WHEN caiu_contra_si AND vizinhanca_estavel AND sinal_violacao_recente
      THEN concat('Consumo caiu ', round(variacao_da_uc, 1), '% frente ao baseline com a vizinhanca estavel (', round(variacao_do_conjunto, 1), '%) e sinal de violacao no medidor nos ultimos 30 dias.')
    WHEN caiu_contra_si AND vizinhanca_estavel
      THEN concat('Consumo caiu ', round(variacao_da_uc, 1), '% frente ao baseline enquanto a vizinhanca ficou estavel (', round(variacao_do_conjunto, 1), '%).')
    WHEN sinal_violacao_recente
      THEN 'Sinal de violacao no medidor nos ultimos 30 dias, sem queda de consumo relevante.'
    ELSE concat('Consumo caiu ', round(variacao_da_uc, 1), '% junto com o conjunto (', round(variacao_do_conjunto, 1), '%) -- padrao de evento de rede, nao caso individual.')
  END AS motivo_observado
FROM avaliado
WHERE caiu_contra_si OR sinal_violacao_recente;
