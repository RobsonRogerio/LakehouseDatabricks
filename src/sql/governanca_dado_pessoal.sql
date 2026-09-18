-- RN-10: a RN-09 protege a ANALISE (texto anonimizado na silver). Esta funcao protege a
-- LEITURA da origem -- quem consulta bronze.chamados direto so ve dado pessoal se estiver
-- no grupo de atendimento. Duas protecoes que coexistem.
--
-- bronze.chamados e materializada pelo pipeline, e um full refresh recria a tabela e
-- derruba a mascara. Por isso esta task roda SEPARADA do pipeline, numa task de job que
-- executa depois dele a cada run -- nunca dentro do pipeline.
--
-- SET MASK nao aceita IDENTIFIER() no nome da funcao (so aceita no nome da tabela), entao
-- essa unica instrucao vai por EXECUTE IMMEDIATE com o nome montado por concatenacao.
--
-- is_member(), nao is_account_group_member(): este workspace (Free Edition) nao expoe
-- console de conta, so grupo de workspace. Atencao ao efeito colateral: o PIPELINE tambem
-- le bronze.chamados para montar a silver, e le como quem o executa. Se quem executa nao
-- estiver em 'atendimento', a silver.chamados_anonimizados recebe transcricao ja mascarada
-- e todo o enriquecimento downstream colapsa -- foi exatamente o que aconteceu aqui antes
-- de eu entrar no grupo. Em producao, quem roda o pipeline (usuario ou service principal)
-- precisa estar no grupo, do contrario RN-09 e RN-10 se cancelam em vez de coexistir.

CREATE OR REPLACE FUNCTION IDENTIFIER(:catalogo || '.' || :schema_bronze || '.mask_dado_pessoal')(valor STRING)
RETURNS STRING
RETURN CASE WHEN is_member('atendimento') THEN valor ELSE '[RESTRITO]' END;

EXECUTE IMMEDIATE
  'ALTER TABLE ' || :catalogo || '.' || :schema_bronze || '.chamados ALTER COLUMN nome_solicitante SET MASK '
  || :catalogo || '.' || :schema_bronze || '.mask_dado_pessoal';

EXECUTE IMMEDIATE
  'ALTER TABLE ' || :catalogo || '.' || :schema_bronze || '.chamados ALTER COLUMN telefone_solicitante SET MASK '
  || :catalogo || '.' || :schema_bronze || '.mask_dado_pessoal';

EXECUTE IMMEDIATE
  'ALTER TABLE ' || :catalogo || '.' || :schema_bronze || '.chamados ALTER COLUMN transcricao SET MASK '
  || :catalogo || '.' || :schema_bronze || '.mask_dado_pessoal';
