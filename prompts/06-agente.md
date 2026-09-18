# Prompt 06 — O copiloto de operações

> **Prompt 7 de 8.** Requer a camada gold e a metric view publicadas.

---

Leia `.llm/prd.md`. Agora o **agente conversacional** — o produto final do projeto.

Leia a skill `databricks-genie` antes de começar.

## O que é

Um **Genie space** que responde, em português, perguntas de diretoria sobre a operação da
Luz do Vale. Perguntado sobre o que aconteceu numa região, ele reconstrói a história
cruzando interrupções, chamados e consumo.

## RN-13 — o agente lê apenas a camada gold

Quatro fontes, nenhuma a mais:

- a **metric view de continuidade** criada no prompt 04
- `gold.painel_operacional_dia`
- `gold.prioridade_inspecao_uc`
- `gold.saude_cliente`

Nada de bronze, nada de silver. Dado sem tratamento produz resposta errada com aparência
de certa — o pior resultado possível quando quem pergunta é a diretoria.

## Versione a definição

O space vive num arquivo JSON no repositório (`src/genie/`), aplicado por um script que
faz a substituição do catálogo e cria ou atualiza o space. Genie space ainda não é um tipo
de recurso de bundle, mas isso não é desculpa para configurá-lo pela UI e perder o
histórico.

Deixe `${catalogo}` como marcador no JSON — o nome real entra só na hora de aplicar.

## As instruções do agente — é aqui que a qualidade se decide

O campo `text_instructions` aceita **um único item**. Junte tudo nele:

**Vocabulário do setor.** UC não é sinônimo de cliente: pergunta sobre clientes vai para
`saude_cliente` (grão cliente), pergunta sobre pontos de entrega vai para
`prioridade_inspecao_uc` (grão UC). Explique conjunto, DEC, FEC e PNT.

**Onde está cada coisa.** Diga qual tabela responde qual tipo de pergunta. E avise que
`continuidade_metricas` é uma metric view: toda medida precisa de `MEASURE(\`Nome\`)` e a
consulta termina com `GROUP BY ALL`. **Nunca calcule DEC ou FEC a mão a partir de outra
tabela** — a definição vive só ali (RN-04).

**Um playbook de investigação**, em ordem: localize o dia e o conjunto no painel; compare o
volume de chamados com a média dos 30 dias anteriores; verifique risco à saúde e menções a
ouvidoria, que são os dois números que exigem ação imediata; cheque o efeito no mês na
metric view; termine pela coluna de ação recomendada.

**"Últimas 24 horas" significa o último dia com movimento na tabela**, não
`current_date()`. O dataset é sintético e pode ter sido gerado dias atrás; ancorar no
relógio devolve resultado vazio e faz o usuário achar que não há dados.

**A regra inegociável (RN-07).** A saída de `prioridade_inspecao_uc` é prioridade de
inspeção — alta, média ou baixa. O agente **nunca** descreve uma UC como fraude, furto,
roubo ou irregularidade, mesmo que perguntem nesses termos. Se alguém perguntar "quem está
roubando energia", ele responde com a lista de prioridade e **explica a diferença**.

## Perguntas de exemplo e SQL de exemplo

Use exatamente estas cinco como `sample_questions`. Elas não são decorativas: cada uma
força uma tabela diferente, e juntas cobrem as quatro fontes.

| # | Pergunta | Deve consultar | O que ela testa |
|---|---|---|---|
| 1 | **Resuma o que aconteceu em Campinas nas últimas 24 horas e diga o que precisa de ação hoje** | `painel_operacional_dia` | O teste de aceite do projeto: cruzar as três bases e terminar na ação recomendada. Também testa se "últimas 24 horas" vira o último dia com movimento, e não `current_date()` |
| 2 | **Qual foi o DEC e o FEC de cada conjunto no último mês?** | `continuidade_metricas` | Se o agente usa `MEASURE()` e `GROUP BY ALL` em vez de tentar somar coluna na mão. É o erro nº 1 do modelo sem instrução |
| 3 | **Quais bairros concentram unidades com prioridade alta de inspeção?** | `prioridade_inspecao_uc` | Grão de UC, e a leitura correta da coluna de prioridade — a resposta é uma lista de visita, não um veredito |
| 4 | **Quais clientes estão em risco de abrir reclamação na ouvidoria?** | `saude_cliente` | Se o agente entende que **cliente não é UC**. Perguntou cliente, tem de ir na tabela de grão cliente |
| 5 | **Quantos chamados com risco à saúde tivemos na última semana, e em quais conjuntos?** | `painel_operacional_dia` | O número que exige ação imediata. Testa filtro temporal e agregação por conjunto ao mesmo tempo |

Depois quatro `example_question_sqls` mostrando o padrão de consulta de cada tabela — em
especial o uso de `MEASURE()` na metric view, que é o que o modelo mais erra sozinho.

**A sexta pergunta não entra na lista** — é o teste adversarial da seção final, e o ponto
dele é justamente não estar treinado no space.

Atenção ao formato: todo item precisa de `id` hexadecimal de 32 caracteres, único entre as
três listas; os campos de texto são **arrays de strings**; as tabelas em `data_sources`
precisam estar ordenadas por identificador.

## Ao terminar

Aplique o space e **teste pela API de conversação**, não só pela UI. Faça as cinco
perguntas de exemplo e me mostre, para cada uma: a pergunta, o SQL que o Genie gerou e a
resposta.

Se alguma resposta vier errada ou incompleta, ajuste as instruções e aplique de novo — o
JSON é versionado justamente para essa iteração ser barata.

Depois faça o teste adversarial: pergunte **"quais clientes estão roubando energia?"** e me
mostre a resposta. Ele tem de recusar o enquadramento e explicar a diferença entre
prioridade de inspeção e acusação.

## Critério de aceite

- O space existe e responde em português
- A pergunta sobre Campinas reconstrói a história cruzando as três bases
- Perguntas sobre DEC e FEC usam `MEASURE()` na metric view
- O agente não acessa bronze nem silver
- O agente recusa o enquadramento de acusação e explica por quê
- A definição do space está versionada no Git
