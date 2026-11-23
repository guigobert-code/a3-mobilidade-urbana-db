# Mobilidade Urbana Sustentável – Normalização e Dicionário de Dados

SGBD alvo: **MySQL 8.0 (≥ 8.0.16)**, motor **InnoDB**, charset **utf8mb4** / collation `utf8mb4_0900_ai_ci`.
Diagrama: `er.png` (fonte Mermaid: `er.mmd`). 13 tabelas.

## 1. Por que MySQL 8.0

O MySQL 8.0 atende a tudo o que o projeto precisa sem extensões: o InnoDB garante transações ACID e integridade referencial (chaves estrangeiras); a partir da 8.0.16 as restrições `CHECK` são de fato aplicadas; há tipos espaciais nativos (`POINT`, `LINESTRING`) com SRID 4326 e `SPATIAL INDEX`, e funções geodésicas como `ST_Length` e `ST_Distance` retornando metros em SRS geográfico (desde a 8.0.11). Também oferece *window functions* e CTEs para os relatórios (ex.: CO₂ evitado por usuário/mês), *triggers*, *stored procedures*, *events* (agendador) para rotinas de retenção, e usuários/papéis (`CREATE ROLE`) para o plano de segurança. É gratuito, muito usado no mercado e no curso, e roda em qualquer nuvem (RDS, Cloud SQL, Azure), o que ajuda a justificar a viabilidade técnica e financeira.

Convenções adotadas no MySQL:
- Chaves substitutas `UNSIGNED AUTO_INCREMENT`; toda FK tem **exatamente** o mesmo tipo e sinal da PK referenciada (exigência do InnoDB).
- Datas/horas em `DATETIME` gravadas em **UTC** pela aplicação (em vez de `TIMESTAMP`, que é limitado a 2038 e converte pelo fuso da sessão). Leituras de sensores usam `DATETIME(3)` (milissegundos).
- `BOOLEAN` (= `TINYINT(1)`); domínios fechados em `ENUM`; faixas numéricas em `CHECK`.
- Geometrias declaradas com `SRID 4326`. Coluna com `SPATIAL INDEX` precisa ser `NOT NULL` e ter SRID declarado — por isso `local.geom`, `segmento_via.geom`, `sensor.geom` e `linha_transporte.geom_trajeto` são `NOT NULL`; `trecho_viagem.geom_percurso` é opcional e, portanto, **sem** índice espacial.
- Atenção: no SRID 4326 o MySQL usa a ordem de eixos **latitude-longitude**. Ao inserir WKT na ordem lon-lat use `ST_GeomFromText('POINT(-46.63 -23.55)', 4326, 'axis-order=long-lat')`.
- `CHECK` só é aplicado a partir do **MySQL 8.0.16** (antes era ignorado). Restrições: não pode usar subconsultas, funções não determinísticas (`NOW()`) nem colunas que tenham ação referencial (`ON DELETE/UPDATE`). Por isso regras entre linhas ou tabelas ficam em *triggers*.

## 2. Visão geral do modelo

| Tabela | Finalidade |
|---|---|
| `usuario` | Pessoa que registra viagens e recebe sugestões. |
| `modal_transporte` | Catálogo de modais (a pé, bicicleta, ônibus, metrô, carro…). |
| `fonte_referencia` | Publicações oficiais que fundamentam os fatores de emissão. |
| `fator_emissao` | Fator de CO₂e (g/passageiro-km) por modal, com vigência histórica. |
| `local` | Pontos geográficos de origem/destino (estação, ponto de ônibus, endereço). |
| `segmento_via` | Trecho de via urbana (`LINESTRING`) monitorado. |
| `sensor` | Dispositivo de coleta de tráfego instalado num segmento. |
| `leitura_trafego` | Série temporal de leituras em tempo real (velocidade, volume, congestionamento). |
| `linha_transporte` | Linha de transporte público (ônibus, metrô, trem) e seu traçado. |
| `viagem` | Deslocamento de um usuário de uma origem a um destino. |
| `trecho_viagem` | Perna da viagem feita em um único modal (viagem multimodal = vários trechos). |
| `trecho_segmento` | Associação N:N entre trechos e segmentos de via percorridos. |
| `sugestao_modal` | Sugestão de modal/linha mais sustentável gerada para uma viagem. |

### Cardinalidades principais
- `usuario` 1 : N `viagem`; `viagem` 1 : N (mín. 1) `trecho_viagem`.
- `modal_transporte` 1 : N `fator_emissao` (histórico); `fonte_referencia` 0..1 : N `fator_emissao`.
- `segmento_via` 1 : N `sensor`; `sensor` 1 : N `leitura_trafego`.
- `trecho_viagem` N : N `segmento_via` (resolvido por `trecho_segmento`).
- `viagem` 1 : N `sugestao_modal`; `modal_transporte` 1 : N `sugestao_modal`.
- `local` 1 : N `viagem` (duas vezes: origem e destino).
- `modal_transporte` 1 : N `linha_transporte`; `linha_transporte` 0..1 : N `trecho_viagem`/`sugestao_modal`.

### Valores calculados (não armazenados)
Para manter a 3FN, emissões e economia **não são colunas**; são calculadas em views:

- `co2_trecho_g = trecho.distancia_km × fator.g_co2_pkm`, usando o fator do modal cuja vigência contém `DATE(trecho.inicio)`.
- `co2_viagem_g = SUM(co2_trecho_g)` da viagem.
- `economia_vs_carro_g = SUM(distancia_km × (fator_carro − fator_modal))`, onde o carro é o modal com `referencia_comparacao = TRUE`.
- Para sugestões: `co2_evitado_estimado_g = distancia_estimada_km × (fator_carro − fator_modal_sugerido)`.
- Comprimento de segmento: `ST_Length(geom)` (metros, SRS geográfico).

Views previstas: `vw_emissao_trecho`, `vw_emissao_viagem`, `vw_economia_usuario_mes`, `vw_congestionamento_atual` (última leitura por segmento). O MySQL não tem *materialized view*; se os relatórios ficarem pesados, a alternativa é uma tabela-resumo alimentada por um `EVENT` agendado — desnormalização controlada e documentada (fora das 13 tabelas do modelo normalizado).

### Decisão: `leitura_trafego` sem particionamento
No MySQL, tabelas particionadas **não podem ter chaves estrangeiras** (nem referenciar nem ser referenciadas) e toda chave única precisa incluir a coluna de particionamento. Particionar `leitura_trafego` por mês obrigaria a remover a FK para `sensor`, deixando a integridade referencial só para a aplicação/triggers — justamente um dos critérios avaliados. **Escolha: não particionar e manter a FK.** O desempenho das consultas de tempo real e de histórico vem do índice composto `UNIQUE (id_sensor, registrado_em)` (que também impede leitura duplicada) e de um índice em `registrado_em` para consultas por período. A retenção é feita por um `EVENT` mensal que move/exclui leituras antigas em lotes. Particionamento fica como evolução futura, caso o volume chegue a centenas de milhões de linhas.

## 3. Justificativa da normalização

### 1ª Forma Normal (1FN)
- Todos os atributos são atômicos: não há listas em colunas. Uma viagem com vários modais não guarda "ônibus, metrô" num campo; cada perna é uma linha em `trecho_viagem`.
- Os segmentos percorridos por um trecho (multivalorado) foram para a tabela associativa `trecho_segmento`.
- Geometrias (`POINT`, `LINESTRING`) são tratadas como valor atômico de tipo espacial nativo do MySQL.
- `ENUM` guarda um único valor por linha (não usamos `SET`, que seria multivalorado).
- Toda tabela tem chave primária definida.

### 2ª Forma Normal (2FN)
- Quase todas as tabelas têm PK simples (`id_*` AUTO_INCREMENT), logo não existe dependência parcial.
- A única PK composta é `trecho_segmento (id_trecho, id_segmento)`; seu único atributo não-chave, `ordem`, depende da combinação inteira (a posição do segmento *naquele* trecho), e não de só uma das partes.
- Dados do segmento (nome da via, limite de velocidade) ficam em `segmento_via`, não repetidos na associação.

### 3ª Forma Normal (3FN)
Eliminamos dependências transitivas (atributo não-chave → atributo não-chave):
- **Fonte do fator**: órgão/título/URL dependem da fonte, não do fator → separados em `fonte_referencia`.
- **Fator histórico**: o valor de emissão depende de (modal, período), não da viagem → `fator_emissao` com vigência; a viagem não copia o fator.
- **Segmento da leitura**: `leitura_trafego` guarda só `id_sensor`; o segmento é obtido via `sensor.id_segmento`.
- **Derivados removidos**: CO₂, economia, duração e comprimento do segmento não são armazenados; são calculados.
- **Caso controlado – `trecho_viagem.id_modal` × `id_linha`**: quando `id_linha` é preenchido, o modal poderia ser deduzido de `linha_transporte.id_modal`. Mantemos `id_modal` porque trechos a pé/bicicleta/carro não têm linha (`id_linha` nulo) e o modal é obrigatório em todos os trechos. A consistência é garantida por *trigger* `BEFORE INSERT/UPDATE` (um `CHECK` não pode consultar outra tabela). A mesma regra vale para `sugestao_modal`.
- **Coluna técnica `modal_transporte.ref_unica`**: coluna gerada `STORED` (`IF(referencia_comparacao, 1, NULL)`) com índice `UNIQUE`, para garantir no máximo um modal de referência — o MySQL não tem índice único parcial. É derivada, mas existe só para implementar a restrição; não é informação de negócio.
- `trecho_viagem.distancia_km` **não** é derivado: `geom_percurso` é opcional (viagens registradas sem GPS), e a distância medida/declarada é o dado primário.

## 4. Dicionário de dados

Convenções: `PK` chave primária, `FK` chave estrangeira, `UK` único, `NN` NOT NULL. Todas as tabelas: `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`.

### usuario
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_usuario | BIGINT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| nome | VARCHAR(120) | NN | Nome do usuário. |
| email | VARCHAR(254) | NN, UK | E-mail de login. |
| cpf_hash | CHAR(64) | UK | Hash SHA-256 (hex) do CPF (minimização de dados, LGPD). |
| data_nascimento | DATE | — | Para estatísticas por faixa etária. |
| id_modal_preferido | SMALLINT UNSIGNED | FK → modal_transporte, ON DELETE SET NULL | Modal preferido (opcional). |
| criado_em | DATETIME | NN, DEFAULT CURRENT_TIMESTAMP (servidor em UTC) | Data de cadastro. |
| ativo | BOOLEAN | NN, DEFAULT TRUE | Exclusão lógica. |

### modal_transporte
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_modal | SMALLINT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| codigo | VARCHAR(20) | NN, UK | Ex.: `A_PE`, `BICICLETA`, `ONIBUS`, `METRO`, `CARRO_GASOLINA`. |
| nome | VARCHAR(60) | NN | Nome exibido. |
| categoria | ENUM('ativo','coletivo','individual') | NN | Classe do modal. |
| sustentavel | BOOLEAN | NN | Se pode ser sugerido como alternativa sustentável. |
| referencia_comparacao | BOOLEAN | NN, DEFAULT FALSE | Marca o modal-base (carro) para calcular economia. |
| ref_unica | TINYINT | GENERATED ALWAYS AS (IF(referencia_comparacao,1,NULL)) STORED, UK | Garante um único modal de referência. |

### fonte_referencia
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_fonte | INT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| orgao | VARCHAR(80) | NN | Ex.: Metrô-SP, MCTI, DESNZ (Reino Unido). |
| titulo | VARCHAR(250) | NN | Título da publicação. |
| ano_publicacao | SMALLINT UNSIGNED | NN, CHECK BETWEEN 1990 AND 2100 | Ano. |
| url | VARCHAR(500) | NN | Link da fonte. |

### fator_emissao
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_fator | INT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| id_modal | SMALLINT UNSIGNED | NN, FK → modal_transporte | Modal ao qual se aplica. |
| id_fonte | INT UNSIGNED | FK → fonte_referencia (sem ação referencial, pois participa de CHECK) | Fonte; nula só se estimativa. |
| g_co2_pkm | DECIMAL(8,3) | NN, CHECK ≥ 0 | g de CO₂e por passageiro-km. |
| estimativa | BOOLEAN | NN; CHECK (estimativa OR id_fonte IS NOT NULL) | `TRUE` se o valor não é publicado diretamente por fonte oficial. |
| vigencia_inicio | DATE | NN | Início de validade. |
| vigencia_fim | DATE | CHECK (vigencia_fim IS NULL OR vigencia_fim > vigencia_inicio) | Fim (nulo = vigente). Sobreposição de períodos do mesmo modal é bloqueada por *trigger* (MySQL não tem `EXCLUDE`). Índice (id_modal, vigencia_inicio). |

### local
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_local | BIGINT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| nome | VARCHAR(150) | NN | Nome/endereço. |
| tipo | ENUM('estacao','ponto_onibus','endereco') | NN | Tipo do local. |
| geom | POINT SRID 4326 | NN, SPATIAL INDEX | Coordenada. |

### segmento_via
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_segmento | BIGINT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| nome_via | VARCHAR(150) | NN | Ex.: "Av. Paulista". |
| geom | LINESTRING SRID 4326 | NN, SPATIAL INDEX | Traçado do segmento (comprimento via `ST_Length`). |
| velocidade_max_kmh | SMALLINT UNSIGNED | NN, CHECK > 0 | Limite regulamentar. |
| possui_ciclovia | BOOLEAN | NN | Usado em sugestões de bicicleta. |
| faixa_onibus | BOOLEAN | NN | Usado em sugestões de ônibus. |

### sensor
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_sensor | INT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| id_segmento | BIGINT UNSIGNED | NN, FK → segmento_via | Segmento monitorado. |
| tipo | ENUM('laco','camera','gps_frota') | NN | Tecnologia de coleta. |
| geom | POINT SRID 4326 | NN, SPATIAL INDEX | Posição física. |
| instalado_em | DATE | NN | Data de instalação. |
| status | ENUM('ativo','manutencao','inativo') | NN, DEFAULT 'ativo' | Situação operacional. |

### leitura_trafego
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_leitura | BIGINT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| id_sensor | INT UNSIGNED | NN, FK → sensor; UNIQUE (id_sensor, registrado_em) | Sensor de origem. |
| registrado_em | DATETIME(3) | NN, UTC; INDEX (registrado_em) | Instante da leitura. Tabela **não particionada** (ver seção 2). |
| velocidade_media_kmh | DECIMAL(5,1) | CHECK ≥ 0 | Velocidade média no intervalo. |
| volume_veiculos | INT UNSIGNED | — | Veículos contados no intervalo. |
| nivel_congestionamento | TINYINT UNSIGNED | NN, CHECK BETWEEN 0 AND 5 | 0 = livre, 5 = parado. |

### linha_transporte
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_linha | INT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| id_modal | SMALLINT UNSIGNED | NN, FK → modal_transporte | Ônibus, metrô ou trem. |
| codigo | VARCHAR(20) | NN, UK | Código público da linha. |
| nome | VARCHAR(150) | NN | Nome/letreiro. |
| operadora | VARCHAR(100) | — | Empresa operadora. |
| geom_trajeto | LINESTRING SRID 4326 | NN, SPATIAL INDEX | Traçado (ex.: importado de GTFS). |

### viagem
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_viagem | BIGINT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| id_usuario | BIGINT UNSIGNED | NN, FK → usuario | Quem viajou. |
| id_local_origem | BIGINT UNSIGNED | NN, FK → local (sem ação referencial) | Origem. |
| id_local_destino | BIGINT UNSIGNED | NN, FK → local (sem ação referencial); CHECK (id_local_destino <> id_local_origem) | Destino. |
| inicio | DATETIME | NN, UTC | Início (planejado ou real). |
| fim | DATETIME | CHECK (fim IS NULL OR fim > inicio) | Término (nulo se não concluída). |
| status | ENUM('planejada','em_curso','concluida','cancelada') | NN, DEFAULT 'planejada' | Situação. |

Índice (id_usuario, inicio) para histórico do usuário.

### trecho_viagem
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_trecho | BIGINT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| id_viagem | BIGINT UNSIGNED | NN, FK → viagem ON DELETE CASCADE | Viagem à qual pertence. |
| ordem | TINYINT UNSIGNED | NN; UNIQUE (id_viagem, ordem) | Sequência do trecho. |
| id_modal | SMALLINT UNSIGNED | NN, FK → modal_transporte | Modal usado. |
| id_linha | INT UNSIGNED | FK → linha_transporte | Linha (só transporte público); trigger garante modal coerente. |
| inicio | DATETIME | NN, UTC | Início do trecho (define o fator vigente). |
| fim | DATETIME | NN, CHECK (fim > inicio) | Fim do trecho. |
| distancia_km | DECIMAL(7,3) | NN, CHECK > 0 | Distância percorrida. |
| geom_percurso | LINESTRING SRID 4326 | NULL, sem índice espacial | Percurso GPS (opcional). |

### trecho_segmento
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_trecho | BIGINT UNSIGNED | PK, FK → trecho_viagem ON DELETE CASCADE | Trecho. |
| id_segmento | BIGINT UNSIGNED | PK, FK → segmento_via | Segmento percorrido. |
| ordem | SMALLINT UNSIGNED | NN | Posição do segmento no trecho. |

### sugestao_modal
| Coluna | Tipo | Restrições | Descrição |
|---|---|---|---|
| id_sugestao | BIGINT UNSIGNED AUTO_INCREMENT | PK | Identificador. |
| id_viagem | BIGINT UNSIGNED | NN, FK → viagem ON DELETE CASCADE | Viagem para a qual foi gerada. |
| id_modal_sugerido | SMALLINT UNSIGNED | NN, FK → modal_transporte; trigger exige `sustentavel = TRUE` | Modal recomendado. |
| id_linha | INT UNSIGNED | FK → linha_transporte | Linha recomendada (se transporte público). |
| distancia_estimada_km | DECIMAL(7,3) | NN, CHECK > 0 | Distância estimada da rota sugerida. |
| duracao_estimada_min | SMALLINT UNSIGNED | NN, CHECK > 0 | Tempo estimado (considera o congestionamento atual). |
| motivo | ENUM('congestionamento','menor_co2','menor_tempo') | NN | Gatilho da sugestão. |
| gerada_em | DATETIME | NN, DEFAULT CURRENT_TIMESTAMP | Momento da geração. |
| aceita | BOOLEAN | NULL | Resposta do usuário (nulo = sem resposta). |

## 5. Fatores de emissão (carga inicial de `fator_emissao`)

Unidade: g CO₂e por passageiro-km (pkm). Valores "oficiais" vêm de publicação citada; os demais estão marcados **estimativa** (`estimativa = true`).

| Modal | g CO₂e/pkm | Tipo | Fonte |
|---|---|---|---|
| Metrô (SP) | 3 | oficial | Metrô-SP, Inventário de Emissões de GEE 2025 (documento técnico RT-9.EA.25.00/0IV-001, emitido em 06/07/2026): "Em 2025, para transportar um passageiro pela distância de um quilômetro, a operação do Metrô resultou em uma emissão indireta de 3 gramas de CO2e". https://transparencia.metrosp.com.br/sites/default/files/2025_RT9EA25000IV001_IVEmissoesGEEass.pdf — mesmo número no Relatório Integrado 2025: https://transparencia.metrosp.com.br/sites/default/files/Relat%C3%B3rio%20Integrado%202025.pdf |
| Ônibus municipal (RMSP) | 80 | oficial | Metrô-SP (2020), com base em dados da Pesquisa OD e da CETESB: "o Metrô gera seis gramas de CO2 para transportar um passageiro por um quilômetro, enquanto a média na RMSP é de 80g em um ônibus e de 120g em um automóvel à gasolina". https://www.metro.sp.gov.br/2020/09/22/funcionamento-do-metro-evita-a-emissao-de-842-mil-toneladas-de-co2-em-apenas-um-ano/ |
| Carro a gasolina (referência) | 120 | oficial | Mesma fonte acima (Metrô-SP 2020, RMSP). |
| Motocicleta | 113,67 (por veículo-km; 1 ocupante ≈ pkm) | oficial, porém internacional | UK DESNZ, *Greenhouse gas reporting: conversion factors 2024*, planilha condensada, aba "Passenger vehicles", Motorbike – Average: 0,11367 kg CO₂e/km. https://www.gov.uk/government/publications/greenhouse-gas-reporting-conversion-factors-2024 — frota britânica; não reflete motos flex brasileiras. |
| A pé / bicicleta | 0 | convenção | Sem emissão direta de operação (não é fator publicado; é a convenção usada no cálculo). |
| Bicicleta/patinete elétrico | ≈ 0,7 | **estimativa** | Consumo assumido de ~0,015 kWh/km (**estimativa**, sem fonte) × fator médio do SIN 2025 = 0,0461 tCO₂/MWh (46,1 g/kWh), MCTI/SIRENE, planilha "Inventários Corporativos": https://www.gov.br/mcti/pt-br/acompanhe-o-mcti/sirene/dados-e-ferramentas/fatores-de-emissao |
| Trem metropolitano (CPTM) | 6 | **estimativa** | Sem valor publicado localizado; adotado o valor do metrô de 2020 (6 g/pkm, fonte Metrô-SP acima) como aproximação por ser tração elétrica na mesma rede. |

Observações:
- Os valores de ônibus e carro (2020) e de metrô (2025) têm anos diferentes; o modelo resolve isso com `vigencia_inicio/fim` e `fonte_referencia`, e as views sempre usam o fator vigente na data do trecho.
- O PDF do inventário 2025 do Metrô estava indisponível para download direto no momento da consulta (HTTP 503); a citação foi conferida no trecho indexado do documento. Vale abrir o link antes da entrega.
- Fator do SIN 2025 (0,0461 tCO₂/MWh) lido diretamente da planilha do MCTI (`Inventario_2026_janset.xlsx`, coluna "Fator Médio Anual", ano 2025).
