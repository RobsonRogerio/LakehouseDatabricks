-- Cadastro limpo: normaliza classe de consumo, marca bairro ausente sem inventar valor, e
-- descarta UC sem chave ou sem conjunto.
CREATE OR REFRESH STREAMING TABLE ${catalogo}.${schema_silver}.unidades_consumidoras
TBLPROPERTIES ('delta.feature.timestampNtz' = 'supported')
AS SELECT
  * EXCEPT (classe_consumo, bairro),
  lower(trim(classe_consumo))                         AS classe_consumo,
  coalesce(nullif(trim(bairro), ''), 'nao informado') AS bairro
FROM STREAM(${catalogo}.${schema_bronze}.unidades_consumidoras)
WHERE id_uc IS NOT NULL AND id_conjunto IS NOT NULL;
