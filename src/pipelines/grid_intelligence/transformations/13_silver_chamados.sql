-- Rota sem IA (RF-09): extracao por regra, nao por modelo. O que ela nao pega:
--   - ironia e negacao ("que otimo, mais um dia sem luz" vira positivo)
--   - sinonimo fora da lista ("tudo apagado" pega; "fiquei no breu" nao)
--   - motivo composto (quem liga por falta de energia E conta alta recebe um rotulo so)
--   - nome escrito diferente da coluna nome_solicitante (apelido nao casa, e o texto
--     passa identificado -- o caso mais serio, e risco de LGPD, nao so de qualidade)

-- RN-09: o texto perde nome, CPF e telefone antes de qualquer analise de conteudo. O nome
-- sai primeiro via replace com a propria coluna nome_solicitante -- e a unica informacao
-- que o regex sozinho nao pegaria, porque nome nao tem formato fixo. CPF e telefone tem
-- padrao fixo e saem depois. A chave da UC fica: identifica a unidade, nao a pessoa.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.chamados_anonimizados
AS SELECT
  ch.id_chamado,
  ch.id_uc,
  u.id_cliente,
  u.id_conjunto,
  u.bairro,
  u.classe_consumo,
  to_date(ch.abertura)                 AS data_chamado,
  date_format(ch.abertura, 'HH:mm:ss') AS hora_chamado,
  ch.canal,
  ch.duracao_segundos,
  regexp_replace(
    regexp_replace(
      replace(ch.transcricao, ch.nome_solicitante, '[MASCARADO]'),
      '[0-9]{3}\\.[0-9]{3}\\.[0-9]{3}-[0-9]{2}',
      '[MASCARADO]'),
    '\\([0-9]{2}\\)\\s*9?[0-9]{4}-?[0-9]{4}',
    '[MASCARADO]')                     AS transcricao_anonimizada,
  'regras_de_texto'                    AS anonimizado_por
FROM ${catalogo}.${schema_bronze}.chamados ch
JOIN ${catalogo}.${schema_silver}.unidades_consumidoras u ON u.id_uc = ch.id_uc;

-- RF-05: sentimento, motivo, equipamento, risco e urgencia extraidos do texto ja
-- anonimizado (nunca do original). A ordem do CASE de motivo e a regra de negocio: um
-- texto pode casar varios padroes, e risco a saude vem antes de religacao comum porque e a
-- mesma frase com uma pessoa em risco no meio.
CREATE OR REFRESH MATERIALIZED VIEW ${catalogo}.${schema_silver}.chamados_enriquecidos
AS WITH classificado AS (
  SELECT
    id_chamado,
    id_uc,
    CASE
      WHEN transcricao_anonimizada RLIKE '(?i)nao aguento mais|revoltante|um absurdo|pessimo|indignado|lamentavel' THEN 'negative'
      WHEN transcricao_anonimizada RLIKE '(?i)obrigad|agradec|otimo atendimento|parabens'                          THEN 'positive'
      ELSE 'neutral'
    END AS sentimento,
    CASE
      WHEN transcricao_anonimizada RLIKE '(?i)dialise|oxigenio|remedio na geladeira|crianca pequena' THEN 'religacao_urgente'
      WHEN transcricao_anonimizada RLIKE '(?i)escuro|sem energia|apagou|falta de energia|sem luz'    THEN 'falta_energia'
      WHEN transcricao_anonimizada RLIKE '(?i)piscando|oscila|queimou|tensao'                        THEN 'oscilacao_tensao'
      WHEN transcricao_anonimizada RLIKE '(?i)releitura|estimativa|nao bate'                         THEN 'erro_leitura'
      WHEN transcricao_anonimizada RLIKE '(?i)conta veio|dobro|fatura subiu|trezentos reais'         THEN 'fatura_alta'
      WHEN transcricao_anonimizada RLIKE '(?i)poste|galho|lampada da rua'                            THEN 'poste_avariado'
      WHEN transcricao_anonimizada RLIKE '(?i)religacao|religar|paguei'                              THEN 'religacao'
      ELSE 'duvida_cadastral'
    END AS motivo,
    regexp_extract(transcricao_anonimizada, '(?i)(medidor|poste|transformador|cabo|disjuntor)', 1)  AS equipamento_citado,
    transcricao_anonimizada RLIKE '(?i)oxigenio|dialise|remedio|crianca|hospital|faisca|incendio|idoso' AS risco_a_saude,
    transcricao_anonimizada RLIKE '(?i)ouvidoria|aneel|procon|processo'                                 AS ameacou_ouvidoria
  FROM ${catalogo}.${schema_silver}.chamados_anonimizados
)
SELECT
  id_chamado,
  id_uc,
  sentimento,
  motivo,
  equipamento_citado,
  risco_a_saude,
  CASE
    WHEN risco_a_saude                                                   THEN 'alta'
    WHEN motivo IN ('falta_energia', 'religacao_urgente', 'poste_avariado') THEN 'media'
    ELSE 'baixa'
  END AS urgencia,
  ameacou_ouvidoria,
  'regras_de_texto' AS enriquecido_por
FROM classificado;
