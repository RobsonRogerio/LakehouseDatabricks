# Prompt 03-A — Silver: o texto, com IA

> **Prompt 4 de 8, rota com IA.** Requer a silver numérica pronta. Existe uma rota irmã,
> `03-silver-texto-regex.md`, que entrega as mesmas colunas sem chamar modelo nenhum —
> escolha **uma das duas**. Os prompts seguintes funcionam igual nos dois casos.

---

Leia `.llm/prd.md`, inclusive a **diretriz de simplicidade**. Agora a parte da silver que
lida com **texto livre**: as transcrições das ligações para a central de atendimento. É o módulo de IA do projeto.

## O que este prompt cria

| Arquivo | Cria | Tipo | Grão |
|---|---|---|---|
| `src/pipelines/grid_intelligence/transformations/13_silver_chamados.py` | `silver.chamados_anonimizados` | materialized view | um chamado |
| o mesmo arquivo | `silver.chamados_enriquecidos` | materialized view | um chamado |
| `src/sql/governanca_dado_pessoal.sql` | column mask sobre `bronze.chamados` | task de SQL do job | — |

São 2.801 chamados. **Materialized view, não streaming table:** as funções de IA custam
tempo, e reprocessar tudo a cada lote novo seria caro sem necessidade.

O segundo arquivo fica **fora do pipeline**, e a seção da RN-10 explica por quê.

## Duas camadas, nesta ordem, e a ordem importa

1. **Anonimizar** (RN-09) — o texto perde nome, CPF, telefone e endereço
2. **Enriquecer** (RF-05) — sentimento, motivo, urgência e equipamento são extraídos do
   texto **já anonimizado**

Inverter isso mandaria dado pessoal identificado para a análise de conteúdo sem
necessidade nenhuma: sentimento e motivo do chamado não dependem do nome de quem ligou.
A chave da UC já identifica a unidade.

## `silver.chamados_anonimizados`

Use `ai_mask(transcricao, array('person', 'phone', 'address', 'ssn', 'email'))`.

A transcrição carrega nome, CPF e telefone **dentro da frase**, não só em coluna. Se o
mascaramento só limpasse as colunas, seria proteção de fachada.

Traga do cadastro: cliente, conjunto, bairro e classe da UC. Derive data e hora do chamado.

## `silver.chamados_enriquecidos`

A partir do texto anonimizado, extraia:

| Coluna | Como |
|---|---|
| `sentimento` | `ai_analyze_sentiment` |
| `motivo` | `ai_classify` com **rótulos descritos**, não só nomeados |
| `equipamento_citado` | `ai_extract` |
| `risco_a_saude` | termo de risco no texto: oxigênio, diálise, remédio, criança, hospital, faísca, incêndio |
| `urgencia` | alta se há risco à saúde; média para falta de energia, religação urgente e poste avariado; baixa no resto |
| `ameacou_ouvidoria` | o cliente citou ouvidoria, ANEEL, Procon ou processo |

**Descreva os rótulos do `ai_classify`.** É o que faz o classificador acertar entre
`religacao` e `religacao_urgente`, que são a mesma frase com uma pessoa em risco no meio.
Passe também `instructions` dizendo que são ligações para uma distribuidora de energia
brasileira — contexto de domínio melhora a precisão de forma mensurável.

**Nada disso vem pronto da origem.** A base de chamados não tem coluna de sentimento nem
de motivo, de propósito: se viesse pronta, este módulo seria um `SELECT`.

## RF-09 — o caminho sem IA no mesmo arquivo, e por que ele precisa ser Python

O projeto tem de funcionar em workspace sem as funções de IA. Dá para resolver de dois
jeitos: construir só a rota determinística (é o `03-silver-texto-regex.md`, e aí este
prompt não é usado) ou deixar **as duas no mesmo arquivo**, atrás de uma chave. É o que
este prompt pede — assim a mesma base de código roda nos dois workspaces.

Isso **não dá para fazer em SQL**: `${usar_ia}` é substituição de texto, então um `CASE WHEN 'false' = 'true' THEN
ai_analyze_sentiment(...)` continua mencionando a função e falha no parse quando ela não
existe.

Escreva este arquivo em **Python** (`from pyspark import pipelines as dp`). Em Python o
`if` acontece na hora de **definir** o dataset — o ramo não escolhido nem chega a ser
compilado.

Adicione `usar_ia` à `configuration` do pipeline, com padrão `"true"`. Quando `"false"`:

- anonimização por expressão regular, mascarando o nome que o próprio registro carrega em
  coluna mais os padrões de CPF e telefone
- sentimento e motivo por palavra-chave, com listas curtas e deliberadamente grosseiras —
  elas existem para o projeto não travar, não para competir com o modelo

**As colunas produzidas são as mesmas nos dois caminhos.** Muda a qualidade da extração,
não o schema. Registre em cada linha qual caminho foi usado (`anonimizado_por`,
`enriquecido_por`) — quem consulta a tabela precisa saber com o que está lidando.

## RN-10 — a outra metade da proteção

A RN-09 protegeu a análise. Falta proteger a leitura da origem.

Crie uma **column mask** do Unity Catalog: uma função que devolve o valor original para
membros do grupo de atendimento e `[RESTRITO]` para todo o resto. Aplique nas colunas
`nome_solicitante`, `telefone_solicitante` e `transcricao` de `bronze.chamados`.

Quem está no atendimento vê o telefone do cliente — precisa dele para retornar a ligação.
Todo o resto não vê.

**Atenção:** `bronze.chamados` é materializada pelo pipeline, e um full refresh recria a
tabela e derruba a máscara. Ponha isso numa task do job que roda **depois** do pipeline, a
cada execução, e deixe a limitação escrita em comentário.

## Ao terminar

Me mostre:

1. Uma transcrição antes e depois do mascaramento, lado a lado
2. A distribuição de `motivo` e `sentimento`
3. Quantos chamados têm `risco_a_saude` e quantos citaram ouvidoria
4. O resultado de consultar `bronze.chamados` — as colunas mascaradas devem aparecer como
   `[RESTRITO]`, a menos que você esteja no grupo

## Critério de aceite

- Nenhum nome, CPF ou telefone sobrevive em `chamados_anonimizados`
- O enriquecimento lê o texto anonimizado, nunca o original
- Trocar `usar_ia` para `"false"` produz as mesmas colunas, sem erro
- A column mask está aplicada e funciona
- Nenhum nome de modelo de IA aparece no código
