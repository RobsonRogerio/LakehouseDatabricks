# Prompt 03-B — Silver: o texto, sem IA

> **Prompt 4 de 8, rota determinística.** Substitui o `03-silver-texto-ia.md`. Requer a
> silver numérica pronta. Escolha **um dos dois** — os prompts seguintes funcionam igual
> nos dois casos.

---

Leia `.llm/prd.md`, inclusive a **diretriz de simplicidade**. Agora a parte da silver que
lida com **texto livre**: as transcrições das ligações para a central de atendimento. Aqui elas são tratadas sem nenhuma chamada a
modelo — só SQL: expressão regular, `CASE` e agregação.

## O que este prompt cria

As mesmas tabelas da rota com IA, com o mesmo schema:

| Arquivo | Cria | Tipo | Grão |
|---|---|---|---|
| `src/pipelines/grid_intelligence/transformations/13_silver_chamados.sql` | `silver.chamados_anonimizados` | materialized view | um chamado |
| o mesmo arquivo | `silver.chamados_enriquecidos` | materialized view | um chamado |
| `src/sql/governanca_dado_pessoal.sql` | column mask sobre `bronze.chamados` | task de SQL do job | — |

São 2.801 chamados. Aqui o arquivo pode ser **`.sql`**, e não `.py` como na rota com IA: sem
função de IA para desviar por configuração, não há motivo para o `if` em Python.

## Por que existe uma rota determinística

Cada função de IA é **uma inferência por linha**. Com 2.801 chamados e quatro funções na
cadeia, são ~11 mil chamadas ao modelo — o suficiente para uma execução levar dezenas de
minutos e travar uma aula ao vivo. E o PRD exige (RF-09) que o projeto funcione em
workspace onde as funções de IA não estão disponíveis.

| | `03-silver-texto-ia` | Este prompt |
|---|---|---|
| Tempo | dezenas de minutos | segundos |
| Anonimização | entende o texto; pega nome escrito de qualquer jeito | pega o que casa com o padrão |
| Motivo do chamado | classifica por significado | classifica por palavra-chave |
| Reprodutibilidade | varia entre execuções | **idêntica sempre** |
| Custo | tokens | zero |

**Não é um downgrade em tudo.** Determinismo é vantagem real: a mesma entrada dá a mesma
saída, sempre — o que torna o resultado testável, e a aula previsível.

## Duas camadas, nesta ordem, e a ordem importa

1. **Anonimizar** (RN-09) — o texto perde nome, CPF e telefone
2. **Enriquecer** (RF-05) — sentimento, motivo, urgência e equipamento saem do texto **já
   anonimizado**

Inverter isso mandaria dado pessoal identificado para a análise de conteúdo sem
necessidade nenhuma: sentimento e motivo do chamado não dependem do nome de quem ligou.
A chave da UC já identifica a unidade.

## 1. `silver.chamados_anonimizados` — regex no lugar de `ai_mask`

**Isto resolve a RN-09.** Sem esta tabela, qualquer análise de conteúdo lê texto
identificado.

Três padrões, aplicados em sequência sobre `transcricao`:

```sql
regexp_replace(
  regexp_replace(
    replace(transcricao, nome_solicitante, '[MASCARADO]'),
    '[0-9]{3}\\.[0-9]{3}\\.[0-9]{3}-[0-9]{2}',            -- CPF formatado
    '[MASCARADO]'),
  '\\([0-9]{2}\\)\\s*9?[0-9]{4}-?[0-9]{4}',               -- telefone com DDD
  '[MASCARADO]') AS transcricao_anonimizada
```

Por que essa ordem: o **nome sai primeiro**, usando a coluna `nome_solicitante` do próprio
registro — é a informação que o regex sozinho não pegaria, porque nome não tem formato. Os
outros dois têm padrão fixo e saem depois.

**A chave da UC fica.** `UC0001147` identifica a unidade consumidora, não a pessoa — e a
análise precisa dela para juntar com o cadastro.

Traga do cadastro: cliente, conjunto, bairro e classe da UC. Derive data e hora do chamado.

Valide contra o dataset: das 2.801 transcrições, **todas** carregam o nome do solicitante,
1.684 têm CPF e 1.819 têm telefone. Depois da anonimização, uma busca por
`[0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2}` tem de voltar **zero**.

## 2. `silver.chamados_enriquecidos` — `CASE` no lugar de `ai_classify`

As mesmas colunas da rota com IA, derivadas por regra:

| Coluna | Como derivar |
|---|---|
| `sentimento` | `negative` se o texto casa com termos de insatisfação; `positive` com termos de agradecimento; senão `neutral` |
| `motivo` | `CASE` encadeado — a **ordem importa**, ver abaixo |
| `equipamento_citado` | `regexp_extract` com alternação dos equipamentos conhecidos |
| `risco_a_saude` | termo de risco no texto: oxigênio, diálise, remédio, criança, hospital, faísca, incêndio, idoso |
| `urgencia` | alta se há risco à saúde; média para falta de energia, religação urgente, poste avariado; baixa no resto |
| `ameacou_ouvidoria` | ouvidoria, ANEEL, Procon ou processo |

**A ordem do `CASE` é a regra de negócio.** Um texto pode casar com vários padrões, e o
primeiro que casar vence. Coloque o mais específico antes do mais genérico:

```sql
CASE
  -- risco a saude vem ANTES de religacao comum: e a mesma frase
  -- com uma pessoa em risco no meio
  WHEN texto RLIKE '(?i)dialise|oxigenio|remedio na geladeira|crianca pequena'
    THEN 'religacao_urgente'
  WHEN texto RLIKE '(?i)escuro|sem energia|apagou|falta de energia|sem luz'
    THEN 'falta_energia'
  WHEN texto RLIKE '(?i)piscando|oscila|queimou|tensao'
    THEN 'oscilacao_tensao'
  WHEN texto RLIKE '(?i)releitura|estimativa|nao bate'
    THEN 'erro_leitura'
  WHEN texto RLIKE '(?i)conta veio|dobro|fatura subiu|trezentos reais'
    THEN 'fatura_alta'
  WHEN texto RLIKE '(?i)poste|galho|lampada da rua'
    THEN 'poste_avariado'
  WHEN texto RLIKE '(?i)religacao|religar|paguei'
    THEN 'religacao'
  ELSE 'duvida_cadastral'
END AS motivo
```

Use `(?i)` para ignorar maiúsculas, e **teste sem acento**: as transcrições foram geradas
sem acentuação em boa parte das falas.

Grave `anonimizado_por = 'regras_de_texto'` e `enriquecido_por = 'regras_de_texto'` em cada
linha. Quem consulta a tabela precisa saber com o que está lidando — e é isso que permite
comparar as duas rotas depois, se você rodar a versão com IA em paralelo.

**As colunas produzidas são as mesmas nas duas rotas.** Muda a qualidade da extração, não
o schema — é por isso que o gold, o dashboard e o agente não precisam saber qual rota você
escolheu.

## 3. RN-10 — a outra metade da proteção

A RN-09 protegeu a análise. Falta proteger a leitura da origem, e **isso não muda de rota**:
não depende de IA nenhuma.

Crie uma **column mask** do Unity Catalog: uma função que devolve o valor original para
membros do grupo de atendimento e `[RESTRITO]` para todo o resto. Aplique nas colunas
`nome_solicitante`, `telefone_solicitante` e `transcricao` de `bronze.chamados`.

Quem está no atendimento vê o telefone do cliente — precisa dele para retornar a ligação.
Todo o resto não vê.

**Atenção:** `bronze.chamados` é materializada pelo pipeline, e um full refresh recria a
tabela e derruba a máscara. Ponha isso numa task do job que roda **depois** do pipeline, a
cada execução, e deixe a limitação escrita em comentário.

## 4. Onde esta rota perde — e o que fazer com isso

Deixe registrado **em comentário no topo do arquivo** que a extração é por regra, não por
modelo, e o que ela não pega:

- **Ironia e negação.** *"Que ótimo, mais um dia sem luz"* vira `positive`.
- **Sinônimo fora da lista.** *"tá tudo apagado"* pega; *"fiquei no breu"* não.
- **Motivo composto.** Quem liga por falta de energia **e** conta alta recebe um rótulo só.
- **Nome escrito diferente da coluna.** Se o cliente se apresenta com apelido, o regex do
  nome não casa — e o texto passa identificado.

O último é o mais sério, porque é risco de LGPD e não de qualidade. Meça: conte quantas
transcrições anonimizadas ainda contêm o primeiro nome do solicitante e me diga o número.

## O que não fazer agora

**Não construa a camada gold.** Ela é o prompt 04 e não muda entre as rotas: consome
`chamados_enriquecidos` sem saber como as colunas foram preenchidas.

## Ao terminar

1. Rode o pipeline e me mostre o tempo total de execução
2. Uma transcrição antes e depois da anonimização, lado a lado
3. A distribuição de `motivo` e `sentimento`
4. A busca por CPF e telefone na tabela anonimizada — tem de voltar zero
5. Quantas transcrições ainda contêm o nome do solicitante
6. O resultado de consultar `bronze.chamados` — as colunas mascaradas devem aparecer como
   `[RESTRITO]`, a menos que você esteja no grupo

## Critério de aceite

- Nenhuma chamada a função de IA nesta etapa
- O enriquecimento lê o texto anonimizado, nunca o original
- Nenhum CPF ou telefone sobrevive em `chamados_anonimizados`
- As colunas de `chamados_enriquecidos` são as mesmas da rota com IA — o gold não sabe a diferença
- `anonimizado_por` e `enriquecido_por` valem `'regras_de_texto'` em toda linha
- O comentário no topo do arquivo declara as limitações da extração por regra
- A column mask está aplicada e funciona
- Duas execuções seguidas produzem resultado idêntico
