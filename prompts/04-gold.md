# Prompt 04 — Camada gold e a metric view

> **Prompt 5 de 8.** Requer a silver completa — números e texto.
>
> Duas das quatro entregas (`saude_cliente` e `painel_operacional_dia`) dependem dos sinais
> extraídos das transcrições. Eles **não precisam de IA**: menção a ouvidoria/ANEEL/Procon,
> risco à saúde e motivo do chamado são termos explícitos, e uma classificação por termo é
> auditável palavra por palavra — o que em setor regulado vale mais do que alguns pontos de
> acurácia. Se a silver de texto não existir ainda, construa-a por regra determinística
> antes de seguir; leva segundos.

---

Leia `.llm/prd.md`, inclusive a **diretriz de simplicidade**. Agora a **camada gold**: as
entregas de negócio.

Uma ressalva à diretriz, e vale só aqui: **a gold leva `COMMENT`**. Ela é a camada que o
agente conversacional lê, e ali a descrição não é documentação — é o que faz o agente
acertar (RN-14). Continua valendo o resto: sem expectations, sem `CONSTRAINT`, sem CTE que
não precise existir.

Regra de nomenclatura que vale para a camada inteira: **se o nome da tabela não é uma
pergunta de negócio, a entrega ainda não está pronta.**

## O que este prompt cria

Cinco arquivos, cinco objetos. Todos em `src/pipelines/grid_intelligence/transformations/`,
exceto o último:

| Arquivo | Cria | Grão | Pergunta que responde |
|---|---|---|---|
| `20_gold_continuidade.sql` | `gold.continuidade_conjunto_mes` | conjunto × mês | Estamos dentro do limite regulatório este mês? |
| `21_gold_prioridade_inspecao.sql` | `gold.prioridade_inspecao_uc` | uma UC candidata | Quais UCs merecem visita técnica primeiro? |
| `22_gold_saude_cliente.sql` | `gold.saude_cliente` | um cliente | Quais clientes estão em rota de reclamação na ouvidoria? |
| `23_gold_painel_operacional.sql` | `gold.painel_operacional_dia` | conjunto × dia | O que aconteceu ontem e o que precisa de ação hoje? |
| `src/sql/metric_view_continuidade.sql` | `gold.continuidade_metricas` | — | **A definição de DEC e FEC** |

Todas as quatro tabelas são **materialized view**: agregação sobre janela e `GROUP BY` não
cabem em streaming table, que é append-only e enxerga só o lote novo.

O quinto arquivo **fica fora do pipeline** e roda como task de SQL do job. Metric view não é
dataset do Lakeflow.

## 1. Continuidade — e a RN-04, que é a lição central do projeto

### Os dois indicadores, antes do código

Ambos são **médias por unidade consumidora do conjunto**, apuradas por mês (RN-05):

```
        Σ (duracao_horas × qtd_ucs_afetadas)              Σ qtd_ucs_afetadas
DEC  =  ────────────────────────────────────      FEC  =  ──────────────────────
             total de UCs do conjunto                     total de UCs do conjunto

     "quantas horas, em média, cada UC              "quantas vezes, em média, cada UC
      do conjunto ficou sem energia"                 do conjunto ficou sem energia"
```

**O denominador é o total de UCs do conjunto, não a contagem de atingidas.** Um evento de
2 horas que atinge 50 de 800 UCs vale `2 × 50 / 800 = 0,125 h` de DEC — a duração diluída em
toda a base, inclusive em quem não ficou sem luz. É o que torna conjuntos de tamanhos
diferentes comparáveis. Se o denominador fosse "UCs atingidas", o indicador devolveria
sempre a duração média do evento e Sumaré pareceria tão bem atendida quanto Campinas.

O numerador do DEC **já vem pronto da silver**: `uc_horas_interrompidas`, calculado em
`11_silver_interrupcoes.sql`. Aqui ele só é somado.

### `gold.continuidade_conjunto_mes` — as colunas

Grão: uma linha por `(id_conjunto, mes_apuracao)`. Origem: `silver.interrupcoes_validas`
agregada, com `INNER JOIN` em `silver.unidades_consumidoras` para trazer o total de UCs.

| Coluna | O que é | Papel |
|---|---|---|
| `id_conjunto` | chave do conjunto | grão |
| `nome_conjunto`, `municipio` | rótulos legíveis | dimensão do dashboard |
| `mes_apuracao` | `date_trunc('MONTH', inicio)` | grão (RN-05) |
| `total_ucs` | `count(*)` das UCs do conjunto | **denominador** de DEC e FEC |
| `uc_horas_interrompidas` | `sum(duracao_horas × qtd_ucs_afetadas)` | **numerador do DEC** |
| `uc_interrupcoes` | `sum(qtd_ucs_afetadas)` | **numerador do FEC** |
| `qtd_interrupcoes` | `count(*)` dos eventos | contexto |
| `qtd_interrupcoes_climaticas` | eventos com causa climática | separa o que é intempérie |
| `qtd_interrupcoes_programadas` | eventos com aviso prévio | têm tratamento regulatório diferente |
| `maior_duracao_horas` | `max(duracao_horas)` | o pior evento do mês |

Sem expectations. O `INNER JOIN` com o cadastro já garante que todo conjunto tem UC — e
conjunto sem UC dividiria por zero.

### Por que a tabela não tem coluna de DEC

Aqui vem a parte contraintuitiva: **a tabela gold de continuidade não tem coluna
`dec_horas`.**

Se a tabela calculasse o DEC e a metric view calculasse de novo, seriam **duas
definições** — e no dia em que a fórmula mudar, alguém atualiza uma e esquece a outra.
Foi assim que a empresa acabou com três DECs diferentes circulando.

A divisão de trabalho é:

- **a tabela** guarda os **insumos aditivos**: horas-UC interrompidas, interrupções-UC e o
  total de UCs do conjunto. Somar insumo em qualquer recorte dá o número certo.
- **a metric view** guarda a **definição**: `DEC = horas-UC / total de UCs`. Uma só,
  versionada em `src/sql/metric_view_continuidade.sql`, consumida por dashboard, agente e
  relatório.

### A metric view — `gold.continuidade_metricas`

`CREATE OR REPLACE VIEW ... WITH METRICS LANGUAGE YAML`, sobre
`continuidade_conjunto_mes`.

**Dimensões:** `Conjunto` (de `nome_conjunto`), `Codigo do Conjunto`, `Municipio`, `Mes`.

**Medidas — dez, cada uma uma expressão sobre as colunas da tabela acima:**

| Medida | Expressão | Formato |
|---|---|---|
| `DEC` | `SUM(uc_horas_interrompidas) / SUM(total_ucs)` | `#,##0.00` |
| `FEC` | `SUM(uc_interrupcoes) / SUM(total_ucs)` | `#,##0.00` |
| `DEC Acumulado` | ver armadilha 3 — fórmula **diferente** da do `DEC` | `#,##0.00` |
| `Interrupcoes` | `SUM(qtd_interrupcoes)` | `#,##0` |
| `Interrupcoes Climaticas` | `SUM(qtd_interrupcoes_climaticas)` | `#,##0` |
| `Proporcao Climatica` | `SUM(climaticas) / NULLIF(SUM(interrupcoes), 0)` | `0.0%` |
| `Interrupcoes Programadas` | `SUM(qtd_interrupcoes_programadas)` | `#,##0` |
| `Horas UC Interrompidas` | `SUM(uc_horas_interrompidas)` | `#,##0.0` |
| `Maior Interrupcao` | `MAX(maior_duracao_horas)` | `#,##0.00` |
| `Total de UCs` | ver armadilha 3 | `#,##0` |

O `NULLIF` na proporção não é preciosismo: mês sem interrupção nenhuma existe no dataset, e
sem ele a view quebra na divisão por zero.

Coloque `synonyms` nas dimensões e nas medidas principais — `DEC` precisa responder a
"quantas horas sem luz", `Conjunto` a "região". É o que o agente do prompt 06 vai usar para
traduzir a pergunta do gestor. E `comment` em tudo (RN-14).

**Como se consulta:**

```sql
SELECT `Conjunto`, MEASURE(`DEC`), MEASURE(`FEC`)
FROM ${catalogo}.${schema_gold}.continuidade_metricas
WHERE `Mes` = '2026-07-01'
GROUP BY ALL
```

Repare que os nomes têm crase e espaço: a metric view expõe **linguagem de negócio**, e é
por isso que o agente consegue traduzir a pergunta do gestor. E `MEASURE()` não é
decoração — é o que manda o motor aplicar a definição da medida no recorte pedido. Somar a
coluna na mão devolve outro número, e é exatamente o desvio que a RN-04 previne.

Três armadilhas para registrar em comentário no arquivo:

1. O corpo YAML fica dentro de um literal `$$...$$` e **não passa por substituição de
   parâmetro**. Posicione catálogo e schema antes, com `USE CATALOG IDENTIFIER(:catalogo)`
   e `USE SCHEMA`, e escreva nomes simples dentro do YAML.

2. **Nenhum `;` dentro do bloco `$$...$$`, nem mesmo em texto de `comment`.** Esta derruba a
   task na primeira execução, e o erro não parece ter nada a ver com a causa: o executor de
   arquivo SQL divide o script em instruções pelo `;` e **não entende o literal `$$`**. Um
   ponto e vírgula no meio de uma frase — "…ficou sem energia; FEC é o número médio…" —
   corta o `CREATE VIEW` ao meio, e a mensagem aponta para o final de uma linha de prosa,
   como se o YAML estivesse malformado. Use ponto final ou travessão na redação dos
   comentários.

3. Ao agregar vários meses, o denominador se repete uma vez por mês. É isso que faz a
   divisão direta devolver **média mensal**, e não acumulado. Ofereça as duas medidas, com
   fórmulas **diferentes** — escrevê-las iguais é fácil e passa despercebido, porque em um
   único mês as duas devolvem o mesmo número:

   ```
   DEC           = SUM(horas_uc) / SUM(total_ucs)                          -- média mensal
   DEC Acumulado = SUM(horas_uc) / (SUM(total_ucs) / COUNT(DISTINCT mês))  -- total do período
   ```

   Vale o mesmo para `Total de UCs`: some e divida pelo número de meses, senão a base
   aparece multiplicada pelo tamanho do período.

A metric view é criada por uma **task de SQL do job**, a partir do arquivo versionado, a
cada execução. Nunca por um `CREATE VIEW` que alguém rodou na UI.

`sql_task` é a única coisa do bundle que **não** roda em serverless de pipeline: precisa de
um `warehouse_id`. Declare-o como variável no `databricks.yml` — o id sai de
`databricks warehouses list --profile grid_intelligence`.

## 2. Prioridade de inspeção — RN-06, RN-07 e RN-08 juntas

`21_gold_prioridade_inspecao.sql` cria `gold.prioridade_inspecao_uc`, uma linha por UC
candidata. A origem é `silver.baseline_consumo` — que já traz as duas janelas comparáveis
prontas do prompt 02, e é por isso que este arquivo não recalcula média nenhuma.

**Os dois eixos:**

- eixo 1: a UC caiu contra o próprio baseline mais do que o limiar
- eixo 2: **enquanto** a variação do conjunto ficou dentro da faixa de estabilidade

Os dois limiares vêm da `configuration` do pipeline, não escritos no SQL.

**A classificação:**

| Situação | Prioridade |
|---|---|
| Dois eixos + sinal de violação no medidor | alta |
| Dois eixos, sem sinal físico | média |
| Sinal no medidor sem queda relevante | média |
| Caiu junto com a vizinhança | **baixa** — isso é evento de rede, não caso individual |

**As colunas que a decisão precisa carregar.** Uma lista de prioridade que não mostra a
conta não serve para o inspetor:

| Coluna | Para quê |
|---|---|
| `id_uc`, `id_conjunto`, `nome_conjunto`, `bairro`, `classe_consumo` | onde ir |
| `prioridade_inspecao` | alta, média ou baixa |
| `caiu_contra_si`, `vizinhanca_estavel`, `atende_os_dois_eixos` | os dois eixos, explícitos como booleano |
| `sinal_violacao_recente` | o agravante físico |
| `variacao_da_uc`, `variacao_do_conjunto` | **os números que sustentam os booleanos** |
| `consumo_medio_baseline_kwh`, `consumo_medio_recente_kwh` | de quanto para quanto |
| `dias_no_baseline`, `dias_no_periodo_recente` | quanta evidência há por trás |
| `motivo_observado` | a frase em linguagem de negócio |

**A saída é prioridade, nunca acusação (RN-07).** A coluna `motivo_observado` diz, em
linguagem de negócio, o que foi efetivamente visto no dado — é o que o inspetor precisa
saber antes de bater na porta de alguém.

Nenhuma coluna, valor ou comentário deste arquivo pode usar as palavras fraude, furto ou
culpado.

**Regra explicável, não modelo treinado (RN-08).** Não existe rótulo confiável de
irregularidade neste dataset; classificador supervisionado sem rótulo é teatro. Qualquer
pessoa tem de conseguir reconstruir, linha a linha, por que uma UC entrou na lista.

## 3. Saúde do cliente

`22_gold_saude_cliente.sql` cria `gold.saude_cliente` a partir de
`silver.chamados_enriquecidos`.

**O grão é o cliente, não a UC.** Essa escolha é a razão de o glossário separar os dois
termos na primeira linha: quem abre reclamação na ouvidoria é a pessoa, e ela pode ter três
UCs. Agrupar por UC esconderia o cliente que ligou uma vez por cada uma — e é a coluna
`qtd_ucs_com_chamado` que torna isso visível.

Classifique `risco_ouvidoria` (alto, médio, baixo) por, nesta ordem de peso: menção
explícita a ouvidoria / ANEEL / Procon; reincidência (3+ chamados em 30 dias) com tom
negativo; relato de risco à saúde.

**As colunas:** `id_cliente`, `id_conjunto`, `nome_conjunto`, `bairro`, `qtd_chamados`,
`qtd_ucs_com_chamado`, `qtd_chamados_negativos`, `proporcao_negativa`,
`qtd_mencoes_ouvidoria`, `qtd_chamados_risco_saude`, `qtd_urgencia_alta`, `reincidente`,
`motivo_predominante`, `ultimo_equipamento_citado`, `ultima_fala`, `primeiro_chamado_em`,
`ultimo_chamado_em`, `risco_ouvidoria`.

`ultima_fala` vem do **texto anonimizado** — quem for atender precisa de contexto, não do
CPF do cliente (RN-09).

Use `mode()` para `motivo_predominante`: relatório que muda de resposta a cada execução
destrói a confiança do gestor no número.

## 4. Painel operacional do dia

`23_gold_painel_operacional.sql` cria `gold.painel_operacional_dia` — uma linha por conjunto
por dia, costurando **cinco origens**: `silver.interrupcoes_validas`,
`silver.chamados_enriquecidos`, `silver.consumo_diario`, `gold.prioridade_inspecao_uc` e
`silver.unidades_consumidoras`.

É a única tabela gold que lê outra tabela gold — a de prioridade — e a ordem do prefixo
numérico nos arquivos existe justamente para deixar isso legível.

**Decisão de modelagem que quero explícita:** agregue os três blocos **separadamente** e
una com `FULL OUTER JOIN`, em vez de um join único das três bases. Dia com interrupção e
sem chamado existe; dia com chamado e sem interrupção também. Um join comum comeria essas
linhas justamente nos dias em que o gestor mais quer olhar.

Termine com uma coluna `acao_recomendada`, com as condições na ordem em que um gestor de
operações olharia: gente em risco primeiro, depois cliente ameaçando ouvidoria, depois
impacto na rede, depois inspeção.

## Ao terminar

Rode o pipeline e a task da metric view, e me mostre:

1. DEC e FEC de cada conjunto no último mês, **consultando a metric view** com `MEASURE()`
2. Quantas UCs ficaram em prioridade alta e em quais bairros
3. Os clientes em risco alto de ouvidoria
4. O painel do dia dos eventos, com a coluna de ação recomendada

### O que esperar ver, para saber se a conta está certa

O dataset tem **4.000 UCs em 6 conjuntos** e 4 anos de histórico. Com isso, os números saem
nesta ordem de grandeza:

| Recorte | DEC | FEC |
|---|---|---|
| Um mês, um conjunto | 0,03 a 1,3 h | 0,1 a 0,6 |
| Acumulado nos 4 anos | 4,8 a 11 h | 5,3 a 13,4 |

**Se o DEC de um único mês vier na casa das horas, o denominador está errado** — quase
sempre é `qtd_ucs_afetadas` no lugar de `total_ucs`, e o indicador virou "duração média do
evento".

Confira também os totais: `silver.interrupcoes_validas` tem **1.073 linhas** das 1.383 da
bronze, e `sum(qtd_interrupcoes)` na gold tem de bater com essas 1.073.

## Critério de aceite

- A tabela gold de continuidade **não** tem coluna de DEC ou FEC calculado
- A metric view responde `MEASURE(\`DEC\`)` corretamente
- `DEC` e `DEC Acumulado` têm fórmulas diferentes — confira consultando **dois meses ou
  mais**, onde os valores precisam divergir. Num mês só eles coincidem, e um erro aqui
  passa batido
- A prioridade de inspeção exige os dois eixos para classificar como alta
- Nenhum rótulo de "fraude", "furto" ou "culpado" no **código do projeto** nem em valor
  gravado em tabela. Os documentos de regra (`prd.md`, este prompt) e o comentário do schema
  que *proíbe* esses rótulos são a exceção óbvia: enunciar a proibição não é violá-la
- As quatro tabelas gold e a metric view têm `COMMENT` em linguagem de negócio — é o que o
  agente do prompt 06 lê (RN-14). Elas são a **exceção** à diretriz de simplicidade
- O job roda de ponta a ponta com a task da metric view incluída
