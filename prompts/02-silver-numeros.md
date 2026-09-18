# Prompt 02 — Silver: os números

> **Prompt 3 de 8.** Requer a bronze pronta e populada.

---

Leia `.llm/prd.md`, inclusive a **diretriz de simplicidade**. Agora a **camada silver**, na
parte numérica: cadastro, interrupções e consumo. O texto livre dos chamados fica para o
próximo prompt.

## O que este prompt cria

Três arquivos em `src/pipelines/grid_intelligence/transformations/`, quatro tabelas:

| Arquivo | Cria | Tipo | Grão |
|---|---|---|---|
| `10_silver_cadastro.sql` | `silver.unidades_consumidoras` | streaming table | uma UC |
| `11_silver_interrupcoes.sql` | `silver.interrupcoes_validas` | streaming table | um evento que passou na RN-01 |
| `12_silver_consumo.sql` | `silver.consumo_diario` | materialized view | UC × dia |
| `12_silver_consumo.sql` | `silver.baseline_consumo` | materialized view | uma UC |

**Por que 12 é materialized view e os outros dois não:** deduplicar exige olhar todas as
linhas da mesma chave, e baseline exige janela — as duas coisas são batch. Streaming table
enxerga só o lote novo, e serve bem para filtro linha a linha, que é o caso de 10 e 11.

**Sem expectations, sem `CONSTRAINT`, sem `COMMENT`.** Todo descarte desta camada é um
`WHERE` que se lê em voz alta.

## 1. `silver.unidades_consumidoras` — cadastro limpo

Streaming table a partir de `STREAM(bronze.unidades_consumidoras)`.

O gerador estraga uma fração pequena dos cadastros de propósito, e aqui é onde isso se
resolve — três casos, três expressões:

| Problema na origem | O que fazer |
|---|---|
| `classe_consumo` chega como `'  RESIDENCIAL '` | `lower(trim(classe_consumo))` |
| `bairro` chega vazio | `'nao informado'` — **não invente bairro** |
| UC sem chave ou sem conjunto | `WHERE id_uc IS NOT NULL AND id_conjunto IS NOT NULL` |

A normalização da classe não é frescura: sem ela o `GROUP BY` por classe devolve duas
linhas para a mesma classe, e o dashboard mostra "residencial" duas vezes.

Bairro faltando é um problema de cadastro que alguém precisa resolver na origem. Marcar
como `'nao informado'` preserva o fato; preencher com o bairro do vizinho o apagaria.

## 2. `silver.interrupcoes_validas` — a RN-01

**Este é o arquivo mais importante do prompt.** É onde a regra dos 3 minutos vive.

> Somente interrupções **de fornecimento** com duração maior ou igual a 3 minutos entram na
> apuração dos indicadores de continuidade.

O corte é sobre a coluna `duracao_minutos` de `bronze.interrupcoes`. Evento abaixo disso é o
religador atuando — galho na rede, desarme e religamento automático em segundos. O
consumidor vê a luz piscar; não é falta de energia. No dataset são 310 de 1.383 eventos,
22,4%.

A regra inteira é uma linha:

```sql
WHERE duracao_minutos >= ${duracao_minima_interrupcao_min}
```

Três coisas que quero explícitas:

1. **O limiar não pode ser `3` escrito no meio da query.** Ele vem da `configuration` do
   pipeline. A regra é do regulador, não do engenheiro: se a ANEEL mudar o limiar, muda-se
   uma linha de configuração.
2. **O descarte acontece aqui, uma vez.** Se cada área aplicasse o próprio filtro, cada
   uma calcularia um DEC diferente — e divergência de número entre relatórios internos é
   problema real em fiscalização.
3. **As interrupções curtas não somem do mundo:** continuam na bronze, onde qualquer um
   pode contá-las. O que elas não fazem é virar indicador.

Duas linhas de comentário acima do `WHERE`, explicando o religador. É o tipo de decisão que
o código não conta sozinho.

### As colunas derivadas — é aqui que o DEC começa

Filtrar não basta. Este arquivo prepara os insumos que a gold vai apenas somar:

| Coluna derivada | Expressão | Para quê |
|---|---|---|
| `data_evento` | `to_date(inicio)` | grão do painel operacional |
| `mes_apuracao` | `date_trunc('MONTH', inicio)` | grão da apuração (RN-05) |
| `duracao_horas` | `duracao_minutos / 60.0` | o indicador é em horas |
| **`uc_horas_interrompidas`** | `duracao_horas × qtd_ucs_afetadas` | **numerador do DEC (RN-02)** |
| `causa_climatica` | `causa = 'climatica'` | separa intempérie do resto |

**Por que o produto é calculado aqui e não na gold.** `uc_horas_interrompidas` é uma
quantidade **aditiva**: somar em qualquer recorte — mês, conjunto, ano — dá o número certo.
Se o produto fosse feito depois da agregação, seria média de média, que não é. Deixar o
insumo pronto no grão do evento é o que permite à metric view responder corretamente a
qualquer corte que o usuário pedir.

O numerador do FEC não precisa de coluna nova: é `qtd_ucs_afetadas`, que já vem da origem.

## 3. `silver.consumo_diario` — descarte e deduplicação

**Materialized view, não streaming table.** O motivo é concreto: o concentrador reenvia
leituras e a mesma chave `(id_uc, data)` chega duas vezes. Escolher uma das duas exige
olhar todas as linhas daquela chave — isso é batch, não streaming.

O que descartar, num `WHERE` só:

- consumo nulo — medidor sem comunicar no ciclo
- consumo negativo — erro de sinal no registrador
- consumo acima do limite físico da ligação

O **limite físico é definido aqui**, do lado de quem consome o dado, e não herdado do
gerador. Numa distribuidora é assim: quem recebe a telemetria estabelece o que considera
plausível para cada tipo de ligação. Use um `CASE` por classe de consumo.

Para a duplicata, `qualify row_number() over (partition by id_uc, data order by ingerido_em desc) = 1`
resolve em uma linha — não precisa de CTE.

Faça o join com o cadastro para que cada linha já carregue conjunto, bairro e classe — as
regras de perdas não técnicas não deveriam ter de refazer esse join.

## 4. `silver.baseline_consumo` — o insumo dos dois eixos

É a tabela que dá à RN-06 as duas comparações:

- **janela recente:** os últimos 30 dias do dataset
- **janela baseline:** os **90 dias imediatamente anteriores** a ela

### Por que o baseline não é "tudo que veio antes" — leia antes de simplificar

A carga da Luz do Vale cresce ~30% ao ano e o dataset tem quatro anos. Comparar os últimos
30 dias contra a média de todo o histórico acusa **alta de mais de 50% em toda UC do
sistema**, porque a média inclui o primeiro ano, quando o consumo era quase três vezes
menor. Resultado prático: o segundo eixo da RN-06 nunca considera a vizinhança estável e a
detecção de perdas para de funcionar por completo.

Baseline sobre série com tendência precisa de **janela comparável**. Noventa dias
imediatamente anteriores carregam ~4% de crescimento entre o centro de uma janela e o da
outra — ruído pequeno o bastante para a faixa de estabilidade absorver, e período longo o
bastante para a média não balançar com duas semanas atípicas.

### Outra armadilha

Ancore a janela no **maior dia do dataset**, nunca em `current_date()`. O dataset é
sintético e pode ter sido gerado semana passada; ancorar no relógio faz a análise deslizar
para fora do dado e devolver tabela vazia — sintoma clássico e chato de diagnosticar.

Calcule, por UC: média no baseline, média no recente, contagem de dias em cada janela, e a
variação percentual. E, por conjunto, as mesmas médias — é o segundo eixo.

## Ao terminar

Rode o pipeline e me mostre:

1. Quantas interrupções a RN-01 descartou, em número e em percentual — deve ser **310 de
   1.383**, sobrando **1.073**
2. Quantas linhas de consumo foram descartadas, e quantas duplicatas sumiram
3. A variação média do conjunto `CPQ-02` entre as duas janelas — precisa estar perto de
   zero, senão o segundo eixo não vai funcionar no próximo prompt

## Critério de aceite

- O limiar de 3 minutos vem de configuração, não está escrito no SQL
- `silver.interrupcoes_validas` tem 1.073 linhas
- `silver.consumo_diario` não tem consumo nulo, negativo ou acima do limite, nem chave
  `(id_uc, data)` repetida
- A variação do conjunto entre as janelas está dentro de ±10%
- Nenhuma expectation, nenhum `CONSTRAINT`, nenhum `COMMENT`
- Cada arquivo cabe em uma tela e meia
