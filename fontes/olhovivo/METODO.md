# Leituras de tráfego reais: SPTrans Olho Vivo

## Fonte
- **API Olho Vivo v2.1, da SPTrans** (`https://api.olhovivo.sptrans.com.br/v2.1`). O cadastro é gratuito em https://www.sptrans.com.br/desenvolvedores/.
- Endpoint usado: `GET /Posicao`, que devolve a posição GPS atual de toda a frota de ônibus municipal (prefixo do veículo `p`, hora GPS `ta` em UTC, `py`/`px` em WGS84 e linha `c`).
- Autenticação: `POST /Login/Autenticar?token=…`, com o cookie de sessão. O token fica **só** na variável de ambiente `SPTRANS_OLHOVIVO_TOKEN`. Ele não aparece em nenhum arquivo, log ou commit.

## Coleta (`scripts/coletar_posicoes.py`)
- **Data:** 19/11/2026, horário de Brasília (America/Sao_Paulo, UTC−3).
- **Blocos de coleta:** 08:33:49–08:45:21, 08:52:06–08:58:36 e 09:05:47–09:17:18. O processo de coleta parou duas vezes, sem relação com a API, e foi reiniciado.
- **Snapshots:** 62, um a cada ~30 s. Um deles veio como `null` (falha transitória da API) e foi descartado, ficando 61 válidos.
- **Volume:** 697.315 posições brutas, ou 500.263 únicas pelo par (veículo, hora GPS), de 11.835 ônibus.
- Os brutos estão em `raw/posicao_AAAAMMDDTHHMMSS-0300.json.gz` (~14 MB), sem nenhuma alteração.

## Processamento (`scripts/processar_olhovivo.py`)
1. **Segmentos:** usamos os 10 `segmento_via` reais do OpenStreetMap (ODbL), lidos do próprio `06_seed.sql`.
2. **Buffer:** para cada segmento, ficam as posições a até **50 m** do eixo OSM. A distância é calculada ponto–polilinha numa projeção local em metros.
3. **Velocidade:** usamos pares de posições **consecutivas do mesmo ônibus** (mesmo `p`), com as duas posições no buffer e Δt entre 15 e 180 s. A velocidade é `v = distância haversine / Δt`. São descartados:
   - pares com v > 100 km/h (erro de GPS);
   - ônibus que não andaram mais de 50 m em toda a coleta (garagem ou terminal);
   - deslocamentos de mais de 20 m com menos de 50 % ao longo do eixo (ônibus em rua transversal).
4. **Janelas de 5 min** (pelo instante médio do par, na hora GPS). Só se publica a janela com pelo menos **2 ônibus distintos**: um ônibus sozinho, parado num ponto, não representa o trecho.
5. **Mapeamento para `leitura_trafego`:**

| Coluna | Origem | Natureza |
|---|---|---|
| `registrado_em` | início da janela, em UTC (o banco roda em `+00:00`) | real |
| `velocidade_media_kmh` | média das velocidades dos pares na janela | **real**, mas é velocidade de **ônibus**, incluindo paradas em pontos e semáforos |
| `volume_veiculos` | nº de **ônibus distintos** observados no trecho | **real**, mas **não** é a contagem total de veículos da via |
| `nivel_congestionamento` | regra do projeto: r = v / `velocidade_max_kmh`; r≥0,70→0, ≥0,55→1, ≥0,40→2, ≥0,25→3, ≥0,10→4, <0,10→5 | **derivado**, não medido (a coluna é NOT NULL) |

6. **Sensores:** os 10 sensores passam a ser **sensores virtuais** do tipo `gps_frota` alimentados pelo Olho Vivo. Os ids, os segmentos e o `geom` (ponto médio do segmento) continuam os mesmos, e `instalado_em` passa a ser 2026-11-19, o início da coleta. Um sensor sem nenhuma janela publicável fica `inativo` e sem leituras. Nenhum valor é inventado.

## Resultado

| sensor/segmento | via | comprimento | posições no buffer | pares válidos | ônibus | linhas | leituras | v média dos pares |
|---|---|---|---|---|---|---|---|---|
| 1 | Av. Paulista (way 261785599) | 293 m | 184 | 88 | 53 | 22 | 8 | 7,2 km/h |
| 2 | Av. Paulista (way 231341013) | 216 m | 228 | 87 | 53 | 23 | 7 | 7,9 km/h |
| 3 | Av. Rebouças (way 329094557) | 480 m | 242 | 147 | 74 | 17 | 8 | 15,9 km/h |
| 4 | Av. Rebouças (way 426510608) | 325 m | 128 | 50 | 42 | 15 | 7 | 14,6 km/h |
| 5 | R. da Consolação (way 405489974) | 260 m | 265 | 105 | 61 | 27 | 8 | 7,4 km/h |
| 6 | R. da Consolação (way 935573768) | 217 m | 134 | 46 | 41 | 20 | 6 | 18,9 km/h |
| 7 | Av. 23 de Maio (way 241249687) | 495 m | 76 | 36 | 32 | 14 | 7 | 26,6 km/h |
| 8 | Av. 23 de Maio (way 286269721) | 407 m | 149 | 67 | 54 | 26 | 8 | 16,1 km/h |
| 9 | Marginal Pinheiros Expressa (way 768961582) | 1.462 m | 23 | 1 | 1 | 1 | **0** | (inativo) |
| 10 | Marginal Pinheiros Expressa (way 96085719) | 1.080 m | 0 | 0 | 0 | 0 | **0** | (inativo) |

São **59 leituras reais** no total, contra 28 simuladas antes.

**Marginal Pinheiros:** as pistas expressas quase não têm ônibus municipais da SPTrans. Os intermunicipais da EMTU não fazem parte do Olho Vivo. Por isso os sensores 9 e 10 ficaram `inativo` e sem leituras. Para cobrir esses trechos seria preciso outra fonte, como a CET-SP (lentidão) ou dados de tráfego geral.

## Limitações (para a prova oral)
- O dado mede o **ônibus**, não o carro. Na Paulista e na Consolação a média fica baixa (~7 km/h) porque o ônibus para nos pontos dentro do trecho.
- O buffer de 50 m pega os dois sentidos da via, mas o eixo OSM tem um sentido só.
- As janelas das pontas e as dos intervalos entre os blocos de coleta ficaram parciais, com menos pares.
- `nivel_congestionamento` é uma classificação derivada; os limiares são uma convenção do projeto.

## Reproduzir
```bash
export SPTRANS_OLHOVIVO_TOKEN=...   # nunca versionar; ver .env.example
mkdir -p fontes/olhovivo/raw
python3 scripts/coletar_posicoes.py 15 30 fontes/olhovivo/raw
python3 scripts/processar_olhovivo.py sql/06_seed.sql fontes/olhovivo/raw 5
# depois: incorporar leitura_trafego_real.sql via importar_dados_reais.py (ou splice no 06_seed)
```
