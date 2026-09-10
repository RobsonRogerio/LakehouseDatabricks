# Prompt 05 — Dashboard AI/BI

> **Prompt 6 de 8.** Requer a camada gold e a metric view publicadas.

---

Leia `.llm/prd.md`. Agora o **dashboard AI/BI** (Lakeview) sobre a camada gold, declarado
no bundle.

Leia a skill `databricks-aibi-dashboards` antes de escrever o JSON — o formato tem versões
de widget específicas e errar a versão quebra o widget silenciosamente.

## Quem abre este dashboard

O gestor de operações da distribuidora, às 8h da manhã, com dois minutos. Ele quer saber
**o que aconteceu** e **o que precisa de ação hoje** — nessa ordem.

## Duas páginas

### Página 1 — Operação do dia

- **Quatro KPIs no topo**, com sparkline: horas-UC sem fornecimento, chamados, chamados com
  risco à saúde, UCs em prioridade de inspeção. Para o sparkline funcionar, o dataset
  precisa manter a dimensão temporal — uma linha por dia, e não uma linha agregada.
- **Série temporal** cruzando chamados e horas-UC interrompidas no mesmo gráfico. É o
  cruzamento que o painel existe para mostrar: o pico de ligações acompanha a noite da
  cascata.
- **Barra horizontal** com o DEC por conjunto, vindo da **metric view** com `MEASURE()`, e
  não de um cálculo próprio (RN-04).
- **Tabela** do que precisa de ação, com a coluna `acao_recomendada`.

### Página 2 — Perdas não técnicas e clientes

Comece a página com um bloco de texto explicando, para quem for olhar, que a classificação
é **prioridade de inspeção e nunca acusação** (RN-07). Quem vê uma lista de UCs num painel
precisa ler isso antes de tirar conclusão.

- **Barra empilhada** de UCs por bairro e prioridade. Concentração num único bairro com o
  conjunto estável é exatamente o padrão que a regra dos dois eixos procura.
- **Tabela** do detalhe da priorização, com o motivo observado.
- **Tabela** de clientes em rota de ouvidoria, com a última fala. Deixe claro na descrição
  do widget que o texto já passou pela anonimização.

## Regras do JSON

- Queries usam **nomes de tabela nus** (`FROM painel_operacional_dia`). Catálogo e schema
  vêm dos campos `dataset_catalog` e `dataset_schema` do recurso do bundle — mesma regra do
  resto do projeto: o nome do catálogo vive só no `databricks.yml`.
- `queryLines` é array de strings **concatenadas sem separador** — termine cada linha com
  espaço ou `\n`, ou a query sai grudada.
- Widgets **inline** em `layout[].widget`, nunca num array `widgets` separado.
- `query.fields[].name` tem de bater exatamente com `encodings.*.fieldName`.
- Versões: `counter` e `table` são versão 2; `bar` e `line` são versão 3.

## Cor

Defina o tema em `uiSettings.theme` — sem isso o dashboard herda o padrão do workspace e
fica genérico. Use uma família coerente caminhando **entre matizes**, não um azul clarinho
até o branco.

Cores semânticas entram como **hex literal** em `color.scale.mappings`: prioridade alta em
coral quente, média em amarelo. Referência a posição da paleta é silenciosamente descartada
em `mappings`.

## Ao terminar

1. **Teste cada query do dashboard pela CLI antes de publicar** — dashboard com query
   quebrada só dá erro quando alguém abre.
2. `databricks bundle deploy -t dev --profile grid_intelligence`
3. Me mande o link do dashboard e um print da página 1

## Critério de aceite

- Todas as queries rodam sem erro contra a gold
- O DEC do dashboard vem da metric view, não de cálculo próprio
- Nenhum nome de catálogo dentro do JSON
- A página 2 avisa que a saída é prioridade de inspeção, não acusação
- O dashboard abre e os widgets renderizam
