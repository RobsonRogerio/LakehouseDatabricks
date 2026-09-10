-- RN-04: a definicao unica de DEC e FEC, consumida por dashboard, agente e relatorio.
-- Fora do pipeline porque metric view nao e dataset do Lakeflow -- criada por esta task de
-- SQL do job, a partir deste arquivo versionado, a cada execucao. Nunca por um CREATE VIEW
-- rodado na UI.
--
-- Armadilha 1: o corpo YAML fica dentro do literal $$...$$ e nao passa por substituicao de
-- parametro. Por isso catalogo e schema sao resolvidos ANTES, com USE CATALOG/USE SCHEMA, e
-- o YAML usa nomes simples (a view e o source ficam no schema corrente).
--
-- Armadilha 2: nenhum ";" dentro do bloco $$...$$, nem em texto de comment - o executor de
-- arquivo SQL divide o script em instrucoes pelo ";" e nao entende o literal $$. Por isso os
-- comentarios do YAML abaixo usam travessao no lugar de ponto e virgula.
--
-- Armadilha 3: DEC e "DEC Acumulado" tem formulas DIFERENTES de proposito. Ao somar varios
-- meses o denominador (total_ucs) se repete uma vez por mes - dividir direto devolve media
-- mensal, nao acumulado. O acumulado divide pelo numero de meses selecionados. Em um unico
-- mes as duas formulas coincidem, e e por isso que testar com dois meses ou mais importa.

USE CATALOG IDENTIFIER(:catalogo);
USE SCHEMA IDENTIFIER(:schema_gold);

CREATE OR REPLACE VIEW continuidade_metricas
COMMENT 'Definicao unica de DEC (horas sem energia por UC) e FEC (interrupcoes por UC) do conjunto - RN-04. Nunca recalcule DEC ou FEC fora daqui.'
WITH METRICS
LANGUAGE YAML
AS $$
version: 1.1
source: continuidade_conjunto_mes
dimensions:
  - name: Conjunto
    expr: nome_conjunto
    display_name: "Conjunto"
    synonyms: ["regiao", "area", "zona"]
    comment: "Nome do conjunto - a subdivisao geografica da area de concessao."
  - name: Codigo do Conjunto
    expr: id_conjunto
    display_name: "Codigo do Conjunto"
    comment: "Codigo do conjunto no cadastro."
  - name: Municipio
    expr: municipio
    display_name: "Municipio"
    synonyms: ["cidade"]
    comment: "Municipio onde o conjunto fica."
  - name: Mes
    expr: mes_apuracao
    display_name: "Mes"
    synonyms: ["mes de apuracao", "periodo"]
    comment: "Mes de apuracao do indicador - RN-05."
measures:
  - name: DEC
    expr: SUM(uc_horas_interrompidas) / SUM(total_ucs)
    display_name: "DEC"
    synonyms: ["duracao equivalente de interrupcao", "quantas horas sem luz", "horas sem energia por consumidor"]
    comment: "Media mensal de horas sem fornecimento por UC do conjunto - RN-04."
    format:
      type: number
  - name: FEC
    expr: SUM(uc_interrupcoes) / SUM(total_ucs)
    display_name: "FEC"
    synonyms: ["frequencia equivalente de interrupcao", "quantas vezes faltou luz"]
    comment: "Media mensal de interrupcoes por UC do conjunto - RN-04."
    format:
      type: number
  - name: DEC Acumulado
    expr: SUM(uc_horas_interrompidas) / (SUM(total_ucs) / COUNT(DISTINCT mes_apuracao))
    display_name: "DEC Acumulado"
    comment: "DEC do periodo inteiro selecionado, nao a media mensal - formula diferente do DEC porque o denominador nao pode se repetir uma vez por mes."
    format:
      type: number
  - name: Interrupcoes
    expr: SUM(qtd_interrupcoes)
    display_name: "Interrupcoes"
    comment: "Total de eventos de interrupcao valida no periodo - ja depois da RN-01."
    format:
      type: number
  - name: Interrupcoes Climaticas
    expr: SUM(qtd_interrupcoes_climaticas)
    display_name: "Interrupcoes Climaticas"
    comment: "Interrupcoes causadas por intemperie."
    format:
      type: number
  - name: Proporcao Climatica
    expr: SUM(qtd_interrupcoes_climaticas) / NULLIF(SUM(qtd_interrupcoes), 0)
    display_name: "Proporcao Climatica"
    comment: "Fatia das interrupcoes causada por clima - NULLIF porque mes sem interrupcao existe no dataset."
    format:
      type: percentage
  - name: Interrupcoes Programadas
    expr: SUM(qtd_interrupcoes_programadas)
    display_name: "Interrupcoes Programadas"
    comment: "Interrupcoes com aviso previo - tratamento regulatorio diferente."
    format:
      type: number
  - name: Horas UC Interrompidas
    expr: SUM(uc_horas_interrompidas)
    display_name: "Horas UC Interrompidas"
    comment: "Numerador do DEC - horas-UC somadas, antes de dividir pelo total de UCs."
    format:
      type: number
  - name: Maior Interrupcao
    expr: MAX(maior_duracao_horas)
    display_name: "Maior Interrupcao"
    comment: "Duracao do pior evento do periodo, em horas."
    format:
      type: number
  - name: Total de UCs
    expr: SUM(total_ucs) / COUNT(DISTINCT mes_apuracao)
    display_name: "Total de UCs"
    comment: "Total de UCs do conjunto - dividido pelo numero de meses selecionados para nao aparecer multiplicado pelo tamanho do periodo."
    format:
      type: number
$$;
