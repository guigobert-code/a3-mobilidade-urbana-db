#!/usr/bin/env python3
"""Deriva leituras de tráfego (velocidade média de ônibus) por segmento_via a partir
dos snapshots brutos de GET /Posicao (SPTrans Olho Vivo v2.1) salvos por coletar_posicoes.py.

Entradas : raw/posicao_*.json.gz  +  sql/06_seed.sql (geometria OSM de segmento_via e sensores)
Saídas   : leitura_trafego_real.sql, resumo.json (estatísticas p/ o relatório)
Não usa token nem rede.

Uso:
  python3 scripts/processar_olhovivo.py sql/06_seed.sql fontes/olhovivo/raw 5
Saídas escritas em fontes/olhovivo/ (leitura_trafego_real.sql, resumo.json).
"""
from pathlib import Path as _Path
_OUT_DIR = _Path(__file__).resolve().parents[1] / "fontes" / "olhovivo"
import sys, os, re, glob, gzip, json, math, datetime, statistics
from collections import defaultdict
from zoneinfo import ZoneInfo

SEED = sys.argv[1]
RAW = sys.argv[2] if len(sys.argv) > 2 else "raw"
JAN_MIN = int(sys.argv[3]) if len(sys.argv) > 3 else 5
BUFFER_M = 50.0        # distância máx. da posição ao eixo OSM do segmento
DT_MIN, DT_MAX = 15, 180   # s entre duas posições consecutivas do mesmo veículo
V_MAX_PLAUS = 100.0    # km/h; acima disso é erro de GPS -> descartado
PARADO_M = 50.0        # veículo que não se moveu > 50 m em toda a coleta = estacionado/garagem
MOV_M, ALINH = 20.0, 0.5  # se andou > 20 m, ao menos 50% do deslocamento deve ser ao longo do eixo
MIN_VEIC = 2           # nº mínimo de ônibus distintos p/ publicar uma leitura (1 ônibus só não representa o trecho)
UTC, SP = datetime.timezone.utc, ZoneInfo("America/Sao_Paulo")
LAT0 = -23.57
KX = 111320.0 * math.cos(math.radians(LAT0)); KY = 110574.0

def xy(lon, lat):
    return (lon * KX, lat * KY)

def hav(lon1, lat1, lon2, lat2):
    R = 6371008.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))

def proj(poly, pt):
    """distância (m) do ponto à polilinha e abscissa curvilínea (m) do pé da perpendicular."""
    best = (1e18, 0.0); acc = 0.0
    px, py = pt
    for (x1, y1), (x2, y2) in zip(poly, poly[1:]):
        dx, dy = x2 - x1, y2 - y1; L2 = dx * dx + dy * dy; L = math.sqrt(L2)
        t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / L2))
        qx, qy = x1 + t * dx, y1 + t * dy
        d = math.hypot(px - qx, py - qy)
        if d < best[0]:
            best = (d, acc + t * L)
        acc += L
    return best

# ---------- segmentos e sensores do seed ----------
seed = open(SEED, encoding="utf-8").read()
seg = {}
blk = seed.split("INSERT INTO segmento_via", 1)[1].split(";\n", 1)[0]
for m in re.finditer(r"\((\d+), '([^']*)', ST_GeomFromText\('LINESTRING\(([^)]*)\)', 4326, 'axis-order=long-lat'\), (\d+), (TRUE|FALSE), (TRUE|FALSE)\)", blk):
    coords = [tuple(map(float, c.split())) for c in m.group(3).split(",")]
    poly = [xy(lo, la) for lo, la in coords]
    L = sum(math.hypot(b[0]-a[0], b[1]-a[1]) for a, b in zip(poly, poly[1:]))
    seg[int(m.group(1))] = dict(nome=m.group(2), coords=coords, poly=poly, L=L, vmax=int(m.group(4)),
        bbox=(min(c[0] for c in coords), min(c[1] for c in coords), max(c[0] for c in coords), max(c[1] for c in coords)))
sens = {}
blk = seed.split("INSERT INTO sensor ", 1)[1].split(";\n", 1)[0]
for m in re.finditer(r"\((\d+), (\d+), '(\w+)', ST_GeomFromText\('POINT\(([^)]*)\)', 4326, 'axis-order=long-lat'\), '([\d-]+)', '(\w+)'\)", blk):
    sens[int(m.group(1))] = dict(seg=int(m.group(2)), pt=m.group(4))
assert len(seg) == 10 and len(sens) == 10, (len(seg), len(sens))

# ---------- snapshots ----------
files = sorted(glob.glob(os.path.join(RAW, "posicao_*.json.gz")))
raw_n = 0; uniq = {}; linhas = {}
snap_ts = []; nulos = []
for f in files:
    d = json.loads(gzip.open(f).read())
    if not isinstance(d, dict):      # a API devolveu "null" (falha transitória) -> snapshot ignorado
        nulos.append(os.path.basename(f)); continue
    snap_ts.append(datetime.datetime.strptime(os.path.basename(f)[8:28], "%Y%m%dT%H%M%S%z"))
    for l in d.get("l", []):
        for v in l["vs"]:
            raw_n += 1
            ta = datetime.datetime.strptime(v["ta"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)
            uniq[(v["p"], ta)] = (v["px"], v["py"], l["c"])
t_ini, t_fim = min(snap_ts), max(snap_ts)
# só posições cuja hora GPS (ta) cai dentro da janela de coleta (−2 min de tolerância)
lim_ini = t_ini - datetime.timedelta(minutes=2)
por_veic = defaultdict(list)
for (p, ta), (lon, lat, c) in uniq.items():
    if lim_ini <= ta <= t_fim:
        por_veic[p].append((ta, lon, lat, c))
uniq_win = sum(len(v) for v in por_veic.values())

# ---------- pares consecutivos -> velocidade ----------
pares = defaultdict(list)   # id_segmento -> [(t_meio, v_kmh, p, linha)]
cand_pos = defaultdict(set)
descart = defaultdict(int)
for p, pts in por_veic.items():
    pts.sort()
    lons = [q[1] for q in pts]; lats = [q[2] for q in pts]
    if len(pts) < 2 or hav(min(lons), min(lats), max(lons), max(lats)) < PARADO_M:
        continue   # estacionado o tempo todo (garagem/terminal)
    for (ta, lo1, la1, c1), (tb, lo2, la2, c2) in zip(pts, pts[1:]):
        dt = (tb - ta).total_seconds()
        for sid, s in seg.items():
            x0, y0, x1, y1 = s["bbox"]; e = 0.001
            if not (x0-e <= lo1 <= x1+e and y0-e <= la1 <= y1+e and x0-e <= lo2 <= x1+e and y0-e <= la2 <= y1+e):
                continue
            dA, sA = proj(s["poly"], xy(lo1, la1)); dB, sB = proj(s["poly"], xy(lo2, la2))
            if dA <= BUFFER_M: cand_pos[sid].add((p, ta))
            if dB <= BUFFER_M: cand_pos[sid].add((p, tb))
            if dA > BUFFER_M or dB > BUFFER_M:
                continue
            if not (DT_MIN <= dt <= DT_MAX):
                descart[(sid, "dt")] += 1; continue
            dist = hav(lo1, la1, lo2, la2)
            if dist > MOV_M and abs(sB - sA) / dist < ALINH:
                descart[(sid, "direcao")] += 1; continue   # andou atravessando o eixo (rua transversal)
            v = dist / dt * 3.6
            if v > V_MAX_PLAUS:
                descart[(sid, "vel")] += 1; continue
            pares[sid].append((ta + (tb - ta) / 2, v, p, c1, abs(sB - sA)))

# ---------- agregação por janela ----------
def janela(t):
    m = (t.minute // JAN_MIN) * JAN_MIN
    return t.replace(minute=m, second=0, microsecond=0)

def nivel(v, vmax):
    """Classificação derivada (regra do projeto) a partir de v/vmax: 0 livre ... 5 parado."""
    r = v / vmax
    if r >= 0.70: return 0
    if r >= 0.55: return 1
    if r >= 0.40: return 2
    if r >= 0.25: return 3
    if r >= 0.10: return 4
    return 5

leit = []; resumo = {}
for sid_sensor, sn in sorted(sens.items()):
    sid = sn["seg"]; s = seg[sid]
    grp = defaultdict(list)
    for t, v, p, c, ds in pares.get(sid, []):
        grp[janela(t)].append((v, p, c))
    rows = []
    for w, lst in sorted(grp.items()):
        if len({x[1] for x in lst}) < MIN_VEIC:
            descart[(sid, "janela_1_onibus")] += 1; continue
        vm = statistics.mean(x[0] for x in lst)
        veic = len({x[1] for x in lst}); lins = sorted({x[2] for x in lst})
        rows.append(dict(w=w, v=round(vm, 1), veic=veic, n=len(lst), lin=lins, niv=nivel(vm, s["vmax"])))
    leit.append((sid_sensor, sid, rows))
    resumo[sid_sensor] = dict(segmento=sid, nome=s["nome"], comprimento_m=round(s["L"]), vmax=s["vmax"],
        posicoes_no_buffer=len(cand_pos[sid]), pares_validos=len(pares.get(sid, [])),
        veiculos=len({x[2] for x in pares.get(sid, [])}), leituras=len(rows),
        linhas=sorted({x[3] for x in pares.get(sid, [])}),
        vel_media_kmh=round(statistics.mean(x[1] for x in pares[sid]), 1) if pares.get(sid) else None)

json.dump(dict(snapshots=len(files), snapshots_nulos=nulos, ini=t_ini.isoformat(), fim=t_fim.isoformat(), posicoes_brutas=raw_n,
               posicoes_unicas=len(uniq), posicoes_unicas_janela=uniq_win, veiculos=len(por_veic),
               janela_min=JAN_MIN, buffer_m=BUFFER_M, sensores=resumo,
               descartes={f"{k[0]}:{k[1]}": n for k, n in descart.items()}),
          open(_OUT_DIR / "resumo.json", "w"), indent=1, ensure_ascii=False, default=str)

# ---------- SQL ----------
fmt = lambda t: t.astimezone(SP).strftime("%d/%m/%Y %H:%M")
o = []
o.append(f"""-- =============================================================================
-- leitura_trafego_real.sql — sensor + leitura_trafego a partir de DADOS REAIS
-- FONTE: SPTrans – API Olho Vivo v2.1 (https://api.olhovivo.sptrans.com.br/v2.1),
--        endpoint GET /Posicao (posição GPS de toda a frota de ônibus de SP).
--        Termos: https://www.sptrans.com.br/desenvolvedores/ (cadastro + token; token NÃO versionado)
-- JANELA DE COLETA (America/Sao_Paulo): {fmt(t_ini)} a {fmt(t_fim)} (UTC−3)
--        {len(files) - len(nulos)} snapshots válidos (~30 s; {len(nulos)} resposta(s) "null" ignorada(s)) | {raw_n} posições brutas | {len(uniq)} posições únicas (veículo, hora GPS)
--        Brutos: fontes/olhovivo/raw/posicao_*.json.gz (coletar_posicoes.py)
-- MÉTODO (processar_olhovivo.py; detalhes em METODO.md):
--   1. Para cada segmento_via (eixo OSM real), posições a ≤ {BUFFER_M:.0f} m do eixo.
--   2. Pares consecutivos do mesmo veículo (prefixo p) com ambas as posições no
--      buffer e Δt entre {DT_MIN} e {DT_MAX} s; v = distância haversine / Δt.
--      Descartados: v > {V_MAX_PLAUS:.0f} km/h (erro GPS), veículos parados a coleta toda
--      e deslocamentos > {MOV_M:.0f} m pouco alinhados ao eixo (< {ALINH:.0%}; rua transversal).
--   3. Agregação em janelas de {JAN_MIN} min (pelo instante médio do par, hora GPS):
--      velocidade_media_kmh = média das velocidades dos pares (REAL, velocidade de ÔNIBUS,
--        inclui paradas em pontos/semáforos — não é a velocidade média de todo o tráfego);
--      volume_veiculos      = nº de ÔNIBUS distintos observados no trecho na janela (REAL,
--        NÃO é a contagem total de veículos da via);
--      nivel_congestionamento = DERIVADO (regra do projeto, não medido):
--        r = velocidade_media_kmh / segmento_via.velocidade_max_kmh;
--        r≥0,70→0 | ≥0,55→1 | ≥0,40→2 | ≥0,25→3 | ≥0,10→4 | <0,10→5.
--   Só publica janela com ≥ {MIN_VEIC} ônibus distintos (1 ônibus parado não representa o trecho).
--   registrado_em = início da janela, em UTC (o banco roda com time_zone '+00:00').
-- SENSORES: cada sensor vira um "sensor virtual" tipo 'gps_frota' alimentado pelo
--   Olho Vivo (ids e segmentos mantidos; geom = ponto médio do segmento OSM, como antes).
--   instalado_em = data de início da coleta. Sensor sem nenhuma janela publicável
--   fica status 'inativo' e sem leituras (não se inventa valor).
-- Gerado em {datetime.datetime.now(SP).strftime('%d/%m/%Y %H:%M')} (America/Sao_Paulo).
-- =============================================================================

USE mobilidade_urbana;
SET time_zone = '+00:00';
SET NAMES utf8mb4;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE leitura_trafego;
TRUNCATE TABLE sensor;
SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- sensor — sensor VIRTUAL 'gps_frota' alimentado pela API Olho Vivo (SPTrans)
-- -----------------------------------------------------------------------------
INSERT INTO sensor (id_sensor, id_segmento, tipo, geom, instalado_em, status) VALUES""")
data_ini = t_ini.astimezone(SP).strftime("%Y-%m-%d")
vals = []
for sid_sensor, sid, rows in leit:
    st = "ativo" if rows else "inativo"
    vals.append(f"({sid_sensor}, {sid}, 'gps_frota', ST_GeomFromText('POINT({sens[sid_sensor]['pt']})', 4326, 'axis-order=long-lat'), '{data_ini}', '{st}')")
o.append(",\n".join(vals) + ";\n")
o.append("""-- -----------------------------------------------------------------------------
-- leitura_trafego — REAL (derivado de GET /Posicao, SPTrans Olho Vivo v2.1)
-- comentário de cada linha: hora local SP | pares usados | linhas de ônibus
-- -----------------------------------------------------------------------------""")
vals = []
for sid_sensor, sid, rows in leit:
    if not rows:
        np_ = len(pares.get(sid, [])); nv_ = len({x[2] for x in pares.get(sid, [])})
        o.append(f"-- sensor {sid_sensor} ({seg[sid]['nome']}): {len(cand_pos[sid])} posição(ões) no buffer, {np_} par(es) válido(s) de {nv_} ônibus -> nenhuma janela com ≥ {MIN_VEIC} ônibus; SEM leituras, sensor 'inativo'")
    for r in rows:
        vals.append((f"({sid_sensor}, '{r['w'].strftime('%Y-%m-%d %H:%M:%S')}.000', {r['v']:.1f}, {r['veic']}, {r['niv']})",
                     f"-- {fmt(r['w'])} SP | {r['n']} par(es) | {', '.join(r['lin'])}"))
if vals:
    o.append("INSERT INTO leitura_trafego (id_sensor, registrado_em, velocidade_media_kmh, volume_veiculos, nivel_congestionamento) VALUES")
    for i, (v, c) in enumerate(vals):
        o.append(v + ("," if i < len(vals) - 1 else ";") + "  " + c)
o.append("")
open(_OUT_DIR / "leitura_trafego_real.sql", "w", encoding="utf-8").write("\n".join(o) + "\n")
print(json.dumps({k: v for k, v in json.load(open(_OUT_DIR / "resumo.json")).items() if k != "sensores"}, ensure_ascii=False))
for k, v in resumo.items():
    print(k, v["nome"][:40], "L=", v["comprimento_m"], "buf=", v["posicoes_no_buffer"], "pares=", v["pares_validos"], "veic=", v["veiculos"], "leit=", v["leituras"], "v=", v["vel_media_kmh"], v["linhas"][:6])
