#!/usr/bin/env python3
"""
Gera sql/06_seed.sql a partir de fontes públicas reais.

Fontes:
  - GTFS SPTrans (espelho Mobility Database mdb-8 / bucket mdb-latest)
    Inclui ônibus SPTrans + Metrô + CPTM no mesmo feed.
  - OpenStreetMap API 0.6 + Nominatim (segmentos viários) — ODbL.

Uso:
  python3 scripts/importar_dados_reais.py
  # cache em data/cache/ ; saída: sql/06_seed.sql

Reexecutar regenera o SQL de forma determinística (mesmas seleções).
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "data" / "cache"
OUT_SQL = ROOT / "sql" / "06_seed.sql"
GTFS_DIR = CACHE / "gtfs_sptrans"
GTFS_ZIP = CACHE / "sptrans_gtfs.zip"
OLHOVIVO_SQL = ROOT / "fontes" / "olhovivo" / "leitura_trafego_real.sql"

# Espelho público (sem login). Produtor oficial: SPTrans BaixarGTFS (requer cadastro).
GTFS_GCS_LIST = (
    "https://storage.googleapis.com/storage/v1/b/mdb-latest/o"
    "?prefix=br-sao-paulo-sao-paulo-transporte-sptrans-gtfs-8.zip"
)
GTFS_OFFICIAL_NOTE = (
    "https://www.sptrans.com.br/desenvolvedores/ "
    "(BaixarGTFS; cadastro). Espelho usado: Mobility Database mdb-8 / GCS mdb-latest."
)

USER_AGENT = "a3-mobilidade-urbana-db/1.0 (academic; contact: github.com/PiNePu447/a3-mobilidade-urbana-db)"

# Subconjunto gerenciável de linhas reais (códigos GTFS)
METRO_ROUTE_IDS = [
    "METRÔ L1",
    "METRÔ L2",
    "METRÔ L3",
    "METRÔ L4",
    "METRÔ L5",
]
CPTM_ROUTE_IDS = [
    "CPTM L07",
    "CPTM L08",
    "CPTM L09",
]
# Apenas rotas com trips+shapes no feed atual (nem todo routes.txt tem viagem).
BUS_ROUTE_IDS = [
    "875A-10",   # Aeroporto - Perdizes
    "702U-22",   # Metrô Butantã - Term. Pq. D. Pedro II (variante ativa no feed)
    "177Y-10",   # Metrô Barra Funda - Pinheiros
    "917H-10",   # Term. Pirituba - Metrô Vl. Mariana
    "675A-10",   # Pq. Sto. Antonio - Metrô São Judas
    "509M-10",   # Jd. Miriam - Term. Princ. Isabel
    "5154-10",   # Term. Sto. Amaro - Term. Princ. Isabel
    "107T-10",   # Metrô Tucuruvi - Term. Pinheiros
    "930P-10",   # Term. Pq. D. Pedro II - Term. Pinheiros
    "2002-10",   # Term. Pq. D. Pedro II - Term. Bandeira
]

# Corredores OSM (consulta Nominatim + API way/full)
CORRIDORS = [
    "Avenida Paulista, São Paulo, Brazil",
    "Avenida Rebouças, São Paulo, Brazil",
    "Rua da Consolação, São Paulo, Brazil",
    "Avenida 23 de Maio, São Paulo, Brazil",
    "Marginal Pinheiros, São Paulo, Brazil",
]

# Estações/pontos preferidos para `local` (match por nome no GTFS stops)
PREFERRED_STOP_NAMES = [
    "Sé",
    "Paulista",
    "Consolação",
    "Pinheiros",
    "Luz",
    "República",
    "Ana Rosa",
    "Tucuruvi",
    "Jabaquara",
    "Vila Madalena",
    "Vila Prudente",
    "Barra Funda",
    "Corinthians-Itaquera",
    "Santo Amaro",
    "Capão Redondo",
    "Chácara Klabin",
    "Paraíso",
    "Brigadeiro",
    "Trianon-Masp",
    "Santana",
]


def http_get(url: str, dest: Path | None = None, retries: int = 4) -> bytes:
    last_err: Exception | None = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
            if dest is not None:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
            return data
        except Exception as e:  # noqa: BLE001
            last_err = e
            time.sleep(2 ** i)
    raise RuntimeError(f"Falha ao baixar {url}: {last_err}")


def resolve_gtfs_url() -> str:
    meta = json.loads(http_get(GTFS_GCS_LIST).decode())
    items = meta.get("items") or []
    if not items:
        raise RuntimeError("Não encontrou objeto GTFS no bucket mdb-latest")
    item = items[0]
    return item["mediaLink"]


def ensure_gtfs() -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    if not GTFS_ZIP.exists() or GTFS_ZIP.stat().st_size < 1_000_000:
        url = resolve_gtfs_url()
        print(f"Baixando GTFS: {url}", file=sys.stderr)
        http_get(url, GTFS_ZIP)
    if GTFS_DIR.exists():
        # reextrai se zip mais novo
        pass
    GTFS_DIR.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(GTFS_ZIP) as zf:
        zf.extractall(GTFS_DIR)
    return GTFS_DIR


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def sql_str(s: str | None) -> str:
    if s is None:
        return "NULL"
    return "'" + s.replace("\\", "\\\\").replace("'", "''") + "'"


def extract_olhovivo_seed_body(path: Path) -> str:
    """Extrai INSERT sensor/leitura de leitura_trafego_real.sql (sem USE/TRUNCATE)."""
    lines = path.read_text(encoding="utf-8").splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.startswith("-- -----------------------------------------------------------------------------") and "sensor" in line.lower():
            start = i
            break
    if start is None:
        for i, line in enumerate(lines):
            if line.startswith("INSERT INTO sensor"):
                start = i
                break
    if start is None:
        raise RuntimeError(f"Bloco sensor não encontrado em {path}")
    return "\n".join(lines[start:]).rstrip() + "\n"


def sql_point(lon: float, lat: float) -> str:
    return (
        f"ST_GeomFromText('POINT({lon:.6f} {lat:.6f})', 4326, 'axis-order=long-lat')"
    )


def sql_linestring(coords: list[tuple[float, float]]) -> str:
    if len(coords) < 2:
        raise ValueError("LINESTRING precisa de ≥2 pontos")
    # MySQL limita bem; downsample
    pts = downsample(coords, 80)
    body = ", ".join(f"{lon:.6f} {lat:.6f}" for lon, lat in pts)
    return f"ST_GeomFromText('LINESTRING({body})', 4326, 'axis-order=long-lat')"


def downsample(coords: list[tuple[float, float]], max_pts: int) -> list[tuple[float, float]]:
    if len(coords) <= max_pts:
        return coords
    out = [coords[0]]
    step = (len(coords) - 1) / (max_pts - 1)
    for i in range(1, max_pts - 1):
        out.append(coords[int(round(i * step))])
    out.append(coords[-1])
    # remove consecutivos iguais
    cleaned = [out[0]]
    for p in out[1:]:
        if p != cleaned[-1]:
            cleaned.append(p)
    if len(cleaned) < 2:
        cleaned = [coords[0], coords[-1]]
    return cleaned


def haversine_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    """a,b = (lon, lat)"""
    lon1, lat1 = map(math.radians, a)
    lon2, lat2 = map(math.radians, b)
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(h))


def path_length_km(coords: list[tuple[float, float]]) -> float:
    return sum(haversine_km(coords[i], coords[i + 1]) for i in range(len(coords) - 1))


def load_shape_points(shapes_path: Path) -> dict[str, list[tuple[float, float]]]:
    by_id: dict[str, list[tuple[int, float, float]]] = defaultdict(list)
    with shapes_path.open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            sid = row["shape_id"]
            seq = int(float(row["shape_pt_sequence"]))
            lat = float(row["shape_pt_lat"])
            lon = float(row["shape_pt_lon"])
            by_id[sid].append((seq, lon, lat))
    out: dict[str, list[tuple[float, float]]] = {}
    for sid, pts in by_id.items():
        pts.sort()
        out[sid] = [(lon, lat) for _, lon, lat in pts]
    return out


def pick_shape_for_route(trips: list[dict], route_id: str, shapes: dict) -> tuple[str, list[tuple[float, float]]]:
    candidates = [t for t in trips if t["route_id"] == route_id and t.get("shape_id")]
    if not candidates:
        raise KeyError(f"Sem trip/shape para {route_id}")
    best_sid = None
    best_coords: list[tuple[float, float]] = []
    best_len = -1.0
    seen = set()
    for t in candidates:
        sid = t["shape_id"]
        if sid in seen:
            continue
        seen.add(sid)
        coords = shapes.get(sid) or []
        if len(coords) < 2:
            continue
        length = path_length_km(coords)
        if length > best_len:
            best_len = length
            best_sid = sid
            best_coords = coords
    if not best_sid:
        raise KeyError(f"Shape inválida para {route_id}")
    return best_sid, best_coords


def nominatim_ways(query: str, limit: int = 8) -> list[dict]:
    cache_file = CACHE / f"nominatim_{hashlib.sha1(query.encode()).hexdigest()[:12]}.json"
    if cache_file.exists():
        return json.loads(cache_file.read_text())
    params = {
        "q": query,
        "format": "json",
        "limit": str(limit),
        "addressdetails": "0",
    }
    url = "https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode(params)
    time.sleep(1.1)  # política de uso Nominatim
    data = json.loads(http_get(url).decode())
    ways = [d for d in data if d.get("osm_type") == "way"]
    cache_file.write_text(json.dumps(ways, ensure_ascii=False, indent=2))
    return ways


def fetch_osm_way(way_id: int) -> dict | None:
    cache_file = CACHE / f"osm_way_{way_id}.json"
    if cache_file.exists():
        return json.loads(cache_file.read_text())
    url = f"https://api.openstreetmap.org/api/0.6/way/{way_id}/full"
    try:
        xml_bytes = http_get(url)
    except Exception as e:  # noqa: BLE001
        print(f"aviso: way {way_id} falhou: {e}", file=sys.stderr)
        return None
    root = ET.fromstring(xml_bytes)
    nodes = {
        n.get("id"): (float(n.get("lon")), float(n.get("lat")))
        for n in root.findall("node")
    }
    way = root.find("way")
    if way is None:
        return None
    tags = {t.get("k"): t.get("v") for t in way.findall("tag")}
    coords = []
    for nd in way.findall("nd"):
        ref = nd.get("ref")
        if ref in nodes:
            coords.append(nodes[ref])
    if len(coords) < 2:
        return None
    obj = {
        "way_id": way_id,
        "tags": tags,
        "coords": coords,
        "length_km": path_length_km(coords),
    }
    cache_file.write_text(json.dumps(obj, ensure_ascii=False))
    return obj


def parse_maxspeed(tags: dict) -> int:
    raw = tags.get("maxspeed") or tags.get("maxspeed:forward") or ""
    m = re.search(r"(\d+)", raw)
    if m:
        v = int(m.group(1))
        return v if 10 <= v <= 140 else 50
    highway = tags.get("highway", "")
    defaults = {
        "motorway": 90,
        "trunk": 70,
        "primary": 50,
        "secondary": 40,
        "tertiary": 40,
        "residential": 30,
    }
    return defaults.get(highway, 50)


def has_cycleway(tags: dict) -> bool:
    keys = [
        "cycleway",
        "cycleway:left",
        "cycleway:right",
        "cycleway:both",
        "bicycle",
    ]
    for k in keys:
        v = (tags.get(k) or "").lower()
        if v and v not in ("no", "none", "dismount"):
            if k == "bicycle" and v in ("yes", "designated", "official"):
                return True
            if k.startswith("cycleway"):
                return True
    return tags.get("highway") == "cycleway"


def has_bus_lane(tags: dict) -> bool:
    for k, v in tags.items():
        lk = k.lower()
        lv = (v or "").lower()
        if "bus" in lk and lv and lv not in ("no", "none"):
            return True
        if lk in ("lanes:bus", "busway", "busway:left", "busway:right") and lv not in (
            "no",
            "none",
            "",
        ):
            return True
    return False


def classify_local_tipo(name: str, stop_id: str) -> str:
    n = name.casefold()
    # heurística: estações metrô/trem costumam ter nomes curtos sem "Terminal"
    if "terminal" in n or "term." in n:
        return "ponto_onibus"
    # IDs altos de ponto de ônibus SPTrans; estações metro/cptm no feed têm ids ~18k-19k
    # Preferimos tipo estacao para nomes icônicos
    iconic = {
        "sé",
        "se",
        "paulista",
        "consolação",
        "consolacao",
        "pinheiros",
        "luz",
        "república",
        "republica",
        "ana rosa",
        "tucuruvi",
        "jabaquara",
        "vila madalena",
        "vila prudente",
        "barra funda",
        "paraíso",
        "paraiso",
        "brigadeiro",
        "trianon-masp",
        "santana",
        "capão redondo",
        "capao redondo",
        "chácara klabin",
        "chacara klabin",
        "santo amaro",
        "corinthians-itaquera",
    }
    if n in iconic or any(x in n for x in ("metrô", "metro", "cptm", "estação", "estacao")):
        return "estacao"
    return "ponto_onibus"


def stop_name_key(name: str) -> str:
    return re.sub(r"\s+", " ", name.strip().casefold())


def build_seed() -> str:
    accessed = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    gtfs_dir = ensure_gtfs()
    routes = {r["route_id"]: r for r in read_csv(gtfs_dir / "routes.txt")}
    trips = read_csv(gtfs_dir / "trips.txt")
    stops = {s["stop_id"]: s for s in read_csv(gtfs_dir / "stops.txt")}
    shapes = load_shape_points(gtfs_dir / "shapes.txt")

    # stop_times: só precisamos dos stops usados nas rotas escolhidas
    wanted_routes = METRO_ROUTE_IDS + CPTM_ROUTE_IDS + BUS_ROUTE_IDS
    for rid in wanted_routes:
        if rid not in routes:
            raise SystemExit(f"Rota GTFS não encontrada: {rid}")

    trip_ids_by_route: dict[str, set[str]] = defaultdict(set)
    for t in trips:
        if t["route_id"] in wanted_routes:
            trip_ids_by_route[t["route_id"]].add(t["trip_id"])
    all_trip_ids = set().union(*trip_ids_by_route.values()) if trip_ids_by_route else set()

    stops_by_route: dict[str, set[str]] = defaultdict(set)
    with (gtfs_dir / "stop_times.txt").open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if row["trip_id"] in all_trip_ids:
                # map trip->route
                pass
    # Build trip->route map
    trip_to_route = {t["trip_id"]: t["route_id"] for t in trips if t["route_id"] in wanted_routes}
    with (gtfs_dir / "stop_times.txt").open(encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            rid = trip_to_route.get(row["trip_id"])
            if rid:
                stops_by_route[rid].add(row["stop_id"])

    # --- linhas ---
    linhas: list[dict] = []
    line_id = 1
    route_to_line_id: dict[str, int] = {}
    for rid in wanted_routes:
        r = routes[rid]
        rtype = r.get("route_type")
        if rtype == "1":
            id_modal = 5  # METRO
            operadora = "Metrô-SP"
        elif rtype == "2":
            id_modal = 6  # TREM
            operadora = "CPTM"
        else:
            id_modal = 4  # ONIBUS
            operadora = "SPTrans"
        shape_id, coords = pick_shape_for_route(trips, rid, shapes)
        codigo = r.get("route_short_name") or rid
        nome = r.get("route_long_name") or codigo
        # códigos metro/cptm mais legíveis
        if rid.startswith("METRÔ"):
            codigo = rid.replace("METRÔ ", "").replace("METRÔ", "L")
            if codigo == "15":
                codigo = "L15-PRATA"
            nome = f"{rid} — {nome}"
            if "ViaQuatro" in nome or "L4" in rid:
                operadora = "ViaQuatro / Metrô-SP"
            if "L5" in rid:
                operadora = "ViaMobilidade / Metrô-SP"
            if "15" in rid:
                operadora = "ViaMobilidade / Metrô-SP"
        elif rid.startswith("CPTM"):
            codigo = rid.replace("CPTM ", "")
            nome = f"{rid} — {nome}"
        linhas.append(
            {
                "id_linha": line_id,
                "id_modal": id_modal,
                "codigo": codigo[:20],
                "nome": nome[:150],
                "operadora": operadora,
                "coords": coords,
                "route_id": rid,
                "shape_id": shape_id,
            }
        )
        route_to_line_id[rid] = line_id
        line_id += 1

    # --- locais: preferidos + extremos das linhas ---
    selected_stops: dict[str, dict] = {}

    def add_stop(stop_id: str) -> None:
        if stop_id in selected_stops or stop_id not in stops:
            return
        s = stops[stop_id]
        selected_stops[stop_id] = s

    # preferred by name (exact/startswith)
    name_index: dict[str, list[str]] = defaultdict(list)
    for sid, s in stops.items():
        name_index[stop_name_key(s["stop_name"])].append(sid)
    for pref in PREFERRED_STOP_NAMES:
        key = stop_name_key(pref)
        if key in name_index:
            add_stop(name_index[key][0])
        else:
            # partial
            for nk, sids in name_index.items():
                if nk == key or nk.startswith(key + " ") or key in nk:
                    add_stop(sids[0])
                    break

    # termini: first/last stop of one trip per route
    for rid in wanted_routes:
        trip = next(t for t in trips if t["route_id"] == rid)
        seq = []
        with (gtfs_dir / "stop_times.txt").open(encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                if row["trip_id"] == trip["trip_id"]:
                    seq.append((int(float(row["stop_sequence"])), row["stop_id"]))
        if not seq:
            continue
        seq.sort()
        add_stop(seq[0][1])
        add_stop(seq[-1][1])
        # a couple mid stops
        if len(seq) > 4:
            add_stop(seq[len(seq) // 3][1])
            add_stop(seq[2 * len(seq) // 3][1])

    # Cap locais
    stop_items = list(selected_stops.items())[:60]
    locais = []
    stop_to_local: dict[str, int] = {}
    for i, (sid, s) in enumerate(stop_items, start=1):
        lat = float(s["stop_lat"])
        lon = float(s["stop_lon"])
        nome = s["stop_name"][:150]
        tipo = classify_local_tipo(nome, sid)
        locais.append(
            {
                "id_local": i,
                "nome": nome,
                "tipo": tipo,
                "lon": lon,
                "lat": lat,
                "stop_id": sid,
            }
        )
        stop_to_local[sid] = i

    # --- segmentos OSM ---
    segmentos = []
    seg_id = 1
    used_ways = set()
    for corridor_q in CORRIDORS:
        ways = nominatim_ways(corridor_q, limit=10)
        fetched = []
        for w in ways:
            wid = int(w["osm_id"])
            if wid in used_ways:
                continue
            obj = fetch_osm_way(wid)
            if not obj:
                continue
            used_ways.add(wid)
            fetched.append(obj)
        # keep up to 2 longest ways per corridor
        fetched.sort(key=lambda o: o["length_km"], reverse=True)
        for obj in fetched[:2]:
            tags = obj["tags"]
            name = tags.get("name") or corridor_q.split(",")[0]
            # avoid tiny stubs
            if obj["length_km"] < 0.05:
                continue
            segmentos.append(
                {
                    "id_segmento": seg_id,
                    "nome_via": name[:150],
                    "coords": obj["coords"],
                    "velocidade_max_kmh": parse_maxspeed(tags),
                    "possui_ciclovia": has_cycleway(tags),
                    "faixa_onibus": has_bus_lane(tags),
                    "osm_way_id": obj["way_id"],
                    "length_km": obj["length_km"],
                }
            )
            seg_id += 1

    if len(segmentos) < 5:
        raise SystemExit(f"Poucos segmentos OSM obtidos: {len(segmentos)}")

    # sensor + leitura_trafego: NÃO regenerar simulados.
    # Fonte real: fontes/olhovivo/leitura_trafego_real.sql (Olho Vivo 19/11/2026).
    # Se os segmentos OSM mudarem, rode scripts/processar_olhovivo.py de novo.
    if not OLHOVIVO_SQL.exists():
        raise SystemExit(f"Arquivo Olho Vivo ausente: {OLHOVIVO_SQL}")
    olho_body = extract_olhovivo_seed_body(OLHOVIVO_SQL)

    # --- usuários / viagens simulados sobre locais/linhas reais ---
    # Escolhe locais por nome quando possível
    def find_local(*names: str) -> int:
        keys = [stop_name_key(n) for n in names]
        for loc in locais:
            if stop_name_key(loc["nome"]) in keys:
                return loc["id_local"]
        return locais[0]["id_local"]

    def find_local_other(exclude: int) -> int:
        for loc in locais:
            if loc["id_local"] != exclude:
                return loc["id_local"]
        return locais[-1]["id_local"]

    loc_se = find_local("Sé", "Se")
    loc_paulista = find_local("Paulista")
    loc_consol = find_local("Consolação", "Consolacao")
    loc_pinheiros = find_local("Pinheiros")
    loc_luz = find_local("Luz")
    loc_ana = find_local("Ana Rosa")
    loc_rep = find_local("República", "Republica")
    loc_vm = find_local("Vila Madalena")

    line_metro1 = route_to_line_id["METRÔ L1"]
    line_metro2 = route_to_line_id["METRÔ L2"]
    line_metro4 = route_to_line_id["METRÔ L4"]
    line_702 = route_to_line_id["702U-22"]
    line_875 = route_to_line_id["875A-10"]

    def dist_between(id_a: int, id_b: int) -> float:
        a = next(l for l in locais if l["id_local"] == id_a)
        b = next(l for l in locais if l["id_local"] == id_b)
        d = haversine_km((a["lon"], a["lat"]), (b["lon"], b["lat"]))
        return max(0.3, round(d, 3))

    # Garante locais 1 e 2 distintos (testes)
    assert locais[0]["id_local"] == 1 and locais[1]["id_local"] == 2

    usuarios = [
        (1, "Ana Fictícia Silva", "ana.ficticia@exemplo.sp.br", "CPF-FAKE-11111111111", "1992-04-12", 5, "2025-08-01 10:00:00"),
        (2, "Bruno Teste Oliveira", "bruno.teste@exemplo.sp.br", "CPF-FAKE-22222222222", "1988-11-03", 2, "2025-09-15 14:30:00"),
        (3, "Carla Demo Souza", "carla.demo@exemplo.sp.br", "CPF-FAKE-33333333333", "1995-07-22", 4, "2025-10-01 09:15:00"),
        (4, "Diego Mock Pereira", "diego.mock@exemplo.sp.br", "CPF-FAKE-44444444444", "1990-01-30", 7, "2025-10-20 16:45:00"),
        (5, "Elena Sample Costa", "elena.sample@exemplo.sp.br", "CPF-FAKE-55555555555", "1998-12-08", 5, "2026-01-05 11:20:00"),
    ]

    # Viagem 7 planejada — exigida pelos testes
    viagens = [
        # id, user, orig, dest, inicio, fim, status
        (1, 1, loc_vm if loc_vm != loc_se else find_local_other(loc_se), loc_se, "2026-11-17 12:00:00", "2026-11-17 12:55:00", "concluida"),
        (2, 2, loc_ana if loc_ana != loc_paulista else find_local_other(loc_paulista), loc_paulista, "2026-11-17 13:10:00", "2026-11-17 13:50:00", "concluida"),
        (3, 3, loc_se, loc_pinheiros if loc_pinheiros != loc_se else find_local_other(loc_se), "2026-11-18 11:00:00", "2026-11-18 11:45:00", "concluida"),
        (4, 4, loc_vm if loc_vm != loc_ana else find_local_other(loc_ana), loc_ana, "2026-11-18 12:00:00", "2026-11-18 12:40:00", "concluida"),
        (5, 5, loc_luz, loc_pinheiros if loc_pinheiros != loc_luz else find_local_other(loc_luz), "2026-11-18 07:30:00", "2026-11-18 08:05:00", "concluida"),
        (6, 1, loc_se, loc_ana if loc_ana != loc_se else find_local_other(loc_se), "2026-11-18 18:00:00", None, "em_curso"),
        (7, 2, loc_consol if loc_consol != loc_pinheiros else find_local_other(loc_pinheiros), loc_pinheiros, "2026-11-19 08:00:00", None, "planejada"),
    ]

    # Ajuste: origem != destino
    for i, v in enumerate(viagens):
        if v[2] == v[3]:
            viagens[i] = (v[0], v[1], v[2], find_local_other(v[2]), v[4], v[5], v[6])

    trechos = []
    # viagem 1: bike + metro L2
    o1, d1 = viagens[0][2], viagens[0][3]
    mid1 = loc_consol if loc_consol not in (o1, d1) else loc_paulista
    if mid1 in (o1, d1):
        mid1 = find_local_other(o1)
    trechos.append((1, 1, 1, 2, None, "2026-11-17 12:00:00", "2026-11-17 12:20:00", dist_between(o1, mid1), True))
    trechos.append((2, 1, 2, 5, line_metro2, "2026-11-17 12:25:00", "2026-11-17 12:55:00", dist_between(mid1, d1), False))
    # viagem 2: bicicleta
    o2, d2 = viagens[1][2], viagens[1][3]
    trechos.append((3, 2, 1, 2, None, "2026-11-17 13:10:00", "2026-11-17 13:50:00", dist_between(o2, d2), False))
    # viagem 3: ônibus 702U-10
    o3, d3 = viagens[2][2], viagens[2][3]
    trechos.append((4, 3, 1, 4, line_702, "2026-11-18 11:00:00", "2026-11-18 11:45:00", dist_between(o3, d3), False))
    # viagem 4: carro
    o4, d4 = viagens[3][2], viagens[3][3]
    trechos.append((5, 4, 1, 7, None, "2026-11-18 12:00:00", "2026-11-18 12:40:00", dist_between(o4, d4), False))
    # viagem 5: metro L4
    o5, d5 = viagens[4][2], viagens[4][3]
    trechos.append((6, 5, 1, 5, line_metro4, "2026-11-18 07:30:00", "2026-11-18 08:05:00", dist_between(o5, d5), False))
    # viagem 6: a pé + metro L1
    o6, d6 = viagens[5][2], viagens[5][3]
    mid6 = loc_rep if loc_rep not in (o6, d6) else loc_luz
    if mid6 in (o6, d6):
        mid6 = find_local_other(o6)
    trechos.append((7, 6, 1, 1, None, "2026-11-18 18:00:00", "2026-11-18 18:10:00", dist_between(o6, mid6), False))
    trechos.append((8, 6, 2, 5, line_metro1, "2026-11-18 18:15:00", "2026-11-18 18:40:00", dist_between(mid6, d6), False))

    # trecho_segmento: associa aos primeiros segmentos OSM
    trecho_segmentos = []
    if segmentos:
        trecho_segmentos = [
            (1, segmentos[0]["id_segmento"], 1),
            (1, segmentos[min(1, len(segmentos) - 1)]["id_segmento"], 2),
            (3, segmentos[0]["id_segmento"], 1),
            (4, segmentos[0]["id_segmento"], 1),
            (4, segmentos[min(1, len(segmentos) - 1)]["id_segmento"], 2),
            (5, segmentos[min(2, len(segmentos) - 1)]["id_segmento"], 1),
            (5, segmentos[min(3, len(segmentos) - 1)]["id_segmento"], 2),
            (6, segmentos[min(1, len(segmentos) - 1)]["id_segmento"], 1),
            (8, segmentos[min(2, len(segmentos) - 1)]["id_segmento"], 1),
        ]
        # dedupe PK
        seen = set()
        uniq = []
        for t in trecho_segmentos:
            if (t[0], t[1]) not in seen:
                seen.add((t[0], t[1]))
                uniq.append(t)
        trecho_segmentos = uniq

    sugestoes = [
        (1, 4, 5, line_metro4, round(dist_between(viagens[3][2], viagens[3][3]) * 0.95, 3), 35, "menor_co2", "2026-11-18 11:55:00", "FALSE"),
        (2, 4, 2, None, round(dist_between(viagens[3][2], viagens[3][3]) * 0.9, 3), 40, "congestionamento", "2026-11-18 11:56:00", "FALSE"),
        (3, 7, 5, line_metro4, round(dist_between(viagens[6][2], viagens[6][3]), 3), 28, "menor_tempo", "2026-11-18 20:00:00", "NULL"),
        (4, 3, 5, line_metro2, round(dist_between(viagens[2][2], viagens[2][3]) * 0.9, 3), 30, "menor_co2", "2026-11-18 10:50:00", "TRUE"),
        (5, 2, 4, line_875, round(dist_between(viagens[1][2], viagens[1][3]) * 1.05, 3), 45, "congestionamento", "2026-11-17 13:00:00", "TRUE"),
    ]

    gtfs_sha = hashlib.sha256(GTFS_ZIP.read_bytes()).hexdigest()[:16]
    lines_out: list[str] = []
    w = lines_out.append

    w("-- =============================================================================")
    w("-- 06_seed.sql – GERADO por scripts/importar_dados_reais.py")
    w("-- Rede (GTFS/OSM): este script. sensor/leitura: fontes/olhovivo/leitura_trafego_real.sql")
    w(f"-- Acesso/geração GTFS/OSM (UTC): {accessed}; Olho Vivo: 2026-11-19")
    w("-- Geometrias: SRID 4326 com axis-order=long-lat")
    w("--")
    w("-- ORIGEM DOS DADOS (real vs simulado)")
    w("-- -----------------------------------------------------------------------------")
    w("-- REAL:")
    w("--   linha_transporte (+ geom_trajeto), local (paradas/estações): GTFS SPTrans")
    w(f"--     Produtor: {GTFS_OFFICIAL_NOTE}")
    w("--     Espelho baixado: GCS mdb-latest (Mobility Database mdb-8)")
    w(f"--     Arquivo local: data/cache/sptrans_gtfs.zip sha256[:16]={gtfs_sha}")
    w("--     Inclui Metrô e CPTM no mesmo feed (route_type 1 e 2).")
    w("--   segmento_via: OpenStreetMap (Nominatim + API 0.6 way/full) — ODbL 1.0")
    w("--     https://www.openstreetmap.org/copyright")
    w("--     Corredores: Paulista, Rebouças, Consolação, 23 de Maio, Marginal Pinheiros")
    w("--   fator_emissao / fonte_referencia: valores REAIS (docs/normalizacao.md)")
    w("--     Metrô-SP, MCTI/SIRENE, UK DESNZ")
    w("--   sensor / leitura_trafego: SPTrans Olho Vivo API v2.1 GET /Posicao")
    w("--     https://api.olhovivo.sptrans.com.br/v2.1 | token só em SPTRANS_OLHOVIVO_TOKEN")
    w("--     Janela 19/11/2026 08:33–09:17 America/Sao_Paulo; 59 leituras; gps_frota;")
    w("--     sensores 9–10 inativos (Marginal sem cobertura SPTrans).")
    w("--     Caveats: v de ônibus (com paradas); volume = nº ônibus; nivel DERIVADO.")
    w("--     Inclusão: fontes/olhovivo/leitura_trafego_real.sql (não regenerar aqui).")
    w("--")
    w("-- SIMULADO (LGPD / domínio interno):")
    w("--   usuario / viagem / trecho_viagem / trecho_segmento / sugestao_modal:")
    w("--     pessoas fictícias; viagens/sugestões ancoradas em locais/linhas/segmentos reais;")
    w("--     distancia_km via haversine entre coordenadas reais.")
    w("--   modal_transporte: catálogo interno do produto.")
    w("-- =============================================================================")
    w("")
    w("USE mobilidade_urbana;")
    w("SET time_zone = '+00:00';")
    w("SET NAMES utf8mb4;")
    w("")
    w("SET FOREIGN_KEY_CHECKS = 0;")
    for t in (
        "sugestao_modal",
        "trecho_segmento",
        "trecho_viagem",
        "viagem",
        "leitura_trafego",
        "sensor",
        "linha_transporte",
        "segmento_via",
        "local",
        "fator_emissao",
        "fonte_referencia",
        "usuario",
        "modal_transporte",
    ):
        w(f"TRUNCATE TABLE {t};")
    w("SET FOREIGN_KEY_CHECKS = 1;")
    w("")

    w("-- -----------------------------------------------------------------------------")
    w("-- Modais (catálogo interno) — SIMULADO/catálogo")
    w("-- -----------------------------------------------------------------------------")
    w("INSERT INTO modal_transporte (id_modal, codigo, nome, categoria, sustentavel, referencia_comparacao) VALUES")
    w("(1, 'A_PE', 'A pé', 'ativo', TRUE, FALSE),")
    w("(2, 'BICICLETA', 'Bicicleta', 'ativo', TRUE, FALSE),")
    w("(3, 'BIKE_ELETRICA', 'Bicicleta/patinete elétrico', 'ativo', TRUE, FALSE),")
    w("(4, 'ONIBUS', 'Ônibus municipal', 'coletivo', TRUE, FALSE),")
    w("(5, 'METRO', 'Metrô', 'coletivo', TRUE, FALSE),")
    w("(6, 'TREM', 'Trem metropolitano (CPTM)', 'coletivo', TRUE, FALSE),")
    w("(7, 'CARRO_GASOLINA', 'Carro a gasolina', 'individual', FALSE, TRUE),")
    w("(8, 'MOTOCICLETA', 'Motocicleta', 'individual', FALSE, FALSE);")
    w("")

    w("-- -----------------------------------------------------------------------------")
    w("-- Fontes e fatores — REAL (docs/normalizacao.md)")
    w("-- -----------------------------------------------------------------------------")
    w("INSERT INTO fonte_referencia (id_fonte, orgao, titulo, ano_publicacao, url) VALUES")
    w("(1, 'Metrô-SP', 'Inventário de Emissões de GEE 2025 (RT-9.EA.25.00/0IV-001)', 2025,")
    w(" 'https://transparencia.metrosp.com.br/sites/default/files/2025_RT9EA25000IV001_IVEmissoesGEEass.pdf'),")
    w("(2, 'Metrô-SP', 'Funcionamento do Metrô evita a emissão de 842 mil toneladas de CO2 em apenas um ano (RMSP: ônibus 80g, carro 120g)', 2020,")
    w(" 'https://www.metro.sp.gov.br/2020/09/22/funcionamento-do-metro-evita-a-emissao-de-842-mil-toneladas-de-co2-em-apenas-um-ano/'),")
    w("(3, 'UK DESNZ', 'Greenhouse gas reporting: conversion factors 2024 – Passenger vehicles – Motorbike Average', 2024,")
    w(" 'https://www.gov.uk/government/publications/greenhouse-gas-reporting-conversion-factors-2024'),")
    w("(4, 'MCTI/SIRENE', 'Fator médio anual do SIN 2025 (Inventários Corporativos) – 0,0461 tCO2/MWh', 2025,")
    w(" 'https://www.gov.br/mcti/pt-br/acompanhe-o-mcti/sirene/dados-e-ferramentas/fatores-de-emissao');")
    w("")
    w("INSERT INTO fator_emissao (id_modal, id_fonte, g_co2_pkm, estimativa, vigencia_inicio, vigencia_fim) VALUES")
    w("(1, NULL, 0.000, TRUE, '2015-01-01', NULL),")
    w("(2, NULL, 0.000, TRUE, '2015-01-01', NULL),")
    w("(3, 4, 0.700, TRUE, '2025-01-01', NULL),")
    w("(4, 2, 80.000, FALSE, '2020-01-01', NULL),")
    w("(5, 2, 6.000, FALSE, '2020-01-01', '2025-01-01'),")
    w("(5, 1, 3.000, FALSE, '2025-01-01', NULL),")
    w("(6, 2, 6.000, TRUE, '2020-01-01', NULL),")
    w("(7, 2, 120.000, FALSE, '2020-01-01', NULL),")
    w("(8, 3, 113.670, FALSE, '2024-01-01', NULL);")
    w("")

    w("-- -----------------------------------------------------------------------------")
    w("-- local — REAL (GTFS stops)")
    w("-- -----------------------------------------------------------------------------")
    w("INSERT INTO local (id_local, nome, tipo, geom) VALUES")
    loc_rows = []
    for loc in locais:
        loc_rows.append(
            f"({loc['id_local']}, {sql_str(loc['nome'])}, {sql_str(loc['tipo'])}, {sql_point(loc['lon'], loc['lat'])})"
        )
    w(",\n".join(loc_rows) + ";")
    w("")

    w("-- -----------------------------------------------------------------------------")
    w("-- segmento_via — REAL (OpenStreetMap ODbL)")
    w("-- -----------------------------------------------------------------------------")
    w("INSERT INTO segmento_via (id_segmento, nome_via, geom, velocidade_max_kmh, possui_ciclovia, faixa_onibus) VALUES")
    seg_rows = []
    for seg in segmentos:
        nome_via = f"{seg['nome_via']} [OSM way {seg['osm_way_id']}]"
        seg_rows.append(
            "("
            f"{seg['id_segmento']}, {sql_str(nome_via)}, "
            f"{sql_linestring(seg['coords'])}, {seg['velocidade_max_kmh']}, "
            f"{'TRUE' if seg['possui_ciclovia'] else 'FALSE'}, "
            f"{'TRUE' if seg['faixa_onibus'] else 'FALSE'}"
            ")"
        )
    w(",\n".join(seg_rows) + ";")
    w("")

    # sensor + leitura_trafego reais (Olho Vivo) — corpo embutido do arquivo fonte
    w(olho_body.rstrip())
    w("")

    w("-- -----------------------------------------------------------------------------")
    w("-- linha_transporte — REAL (GTFS shapes; SPTrans + Metrô + CPTM)")
    w("-- -----------------------------------------------------------------------------")
    w("INSERT INTO linha_transporte (id_linha, id_modal, codigo, nome, operadora, geom_trajeto) VALUES")
    lin_rows = []
    for L in linhas:
        lin_rows.append(
            f"({L['id_linha']}, {L['id_modal']}, {sql_str(L['codigo'])}, {sql_str(L['nome'])}, "
            f"{sql_str(L['operadora'])}, {sql_linestring(L['coords'])})"
        )
    w(",\n".join(lin_rows) + ";")
    w("")

    w("-- -----------------------------------------------------------------------------")
    w("-- usuario — SIMULADO (LGPD; nomes fake)")
    w("-- -----------------------------------------------------------------------------")
    w("INSERT INTO usuario (id_usuario, nome, email, cpf_hash, data_nascimento, id_modal_preferido, criado_em, ativo) VALUES")
    u_rows = []
    for u in usuarios:
        u_rows.append(
            f"({u[0]}, {sql_str(u[1])}, {sql_str(u[2])}, SHA2({sql_str(u[3])}, 256), "
            f"{sql_str(u[4])}, {u[5]}, {sql_str(u[6])}, TRUE)"
        )
    w(",\n".join(u_rows) + ";")
    w("")

    w("-- -----------------------------------------------------------------------------")
    w("-- viagem / trecho — SIMULADO sobre locais/linhas reais; distância haversine")
    w("-- -----------------------------------------------------------------------------")
    w("INSERT INTO viagem (id_viagem, id_usuario, id_local_origem, id_local_destino, inicio, fim, status) VALUES")
    v_rows = []
    for v in viagens:
        fim = "NULL" if v[5] is None else sql_str(v[5])
        v_rows.append(
            f"({v[0]}, {v[1]}, {v[2]}, {v[3]}, {sql_str(v[4])}, {fim}, {sql_str(v[6])})"
        )
    w(",\n".join(v_rows) + ";")
    w("")

    w("INSERT INTO trecho_viagem (id_trecho, id_viagem, ordem, id_modal, id_linha, inicio, fim, distancia_km, geom_percurso) VALUES")
    t_rows = []
    for t in trechos:
        id_linha = "NULL" if t[4] is None else str(t[4])
        geom = "NULL"
        if t[8]:
            # optional geom for first bike leg: straight line between endpoints approx via mid
            # skip heavy geom; leave NULL except flag unused — keep NULL for simplicity
            geom = "NULL"
        t_rows.append(
            f"({t[0]}, {t[1]}, {t[2]}, {t[3]}, {id_linha}, {sql_str(t[5])}, {sql_str(t[6])}, {t[7]:.3f}, {geom})"
        )
    w(",\n".join(t_rows) + ";")
    w("")

    w("INSERT INTO trecho_segmento (id_trecho, id_segmento, ordem) VALUES")
    w(",\n".join(f"({a}, {b}, {c})" for a, b, c in trecho_segmentos) + ";")
    w("")

    w("-- -----------------------------------------------------------------------------")
    w("-- sugestao_modal — SIMULADO (conteúdo de negócio; linhas/modais reais)")
    w("-- -----------------------------------------------------------------------------")
    w("INSERT INTO sugestao_modal (id_sugestao, id_viagem, id_modal_sugerido, id_linha, distancia_estimada_km, duracao_estimada_min, motivo, gerada_em, aceita) VALUES")
    s_rows = []
    for s in sugestoes:
        id_linha = "NULL" if s[3] is None else str(s[3])
        s_rows.append(
            f"({s[0]}, {s[1]}, {s[2]}, {id_linha}, {s[4]:.3f}, {s[5]}, {sql_str(s[6])}, {sql_str(s[7])}, {s[8]})"
        )
    w(",\n".join(s_rows) + ";")
    w("")

    w("SELECT 'Seed concluído (dados reais + simulados)' AS status;")
    w("SELECT 'usuario' AS tabela, COUNT(*) AS n FROM usuario")
    w("UNION ALL SELECT 'modal_transporte', COUNT(*) FROM modal_transporte")
    w("UNION ALL SELECT 'fonte_referencia', COUNT(*) FROM fonte_referencia")
    w("UNION ALL SELECT 'fator_emissao', COUNT(*) FROM fator_emissao")
    w("UNION ALL SELECT 'local', COUNT(*) FROM local")
    w("UNION ALL SELECT 'segmento_via', COUNT(*) FROM segmento_via")
    w("UNION ALL SELECT 'sensor', COUNT(*) FROM sensor")
    w("UNION ALL SELECT 'leitura_trafego', COUNT(*) FROM leitura_trafego")
    w("UNION ALL SELECT 'linha_transporte', COUNT(*) FROM linha_transporte")
    w("UNION ALL SELECT 'viagem', COUNT(*) FROM viagem")
    w("UNION ALL SELECT 'trecho_viagem', COUNT(*) FROM trecho_viagem")
    w("UNION ALL SELECT 'trecho_segmento', COUNT(*) FROM trecho_segmento")
    w("UNION ALL SELECT 'sugestao_modal', COUNT(*) FROM sugestao_modal;")
    w("")
    w("-- Metadados da geração (comentário):")
    w(f"-- linhas GTFS: {len(linhas)} | locais: {len(locais)} | segmentos OSM: {len(segmentos)}")
    w(f"-- route_ids: {', '.join(wanted_routes)}")

    # Write provenance sidecar
    prov = {
        "accessed_utc": accessed,
        "gtfs_sha256_16": gtfs_sha,
        "gtfs_zip": str(GTFS_ZIP.relative_to(ROOT)),
        "n_linhas": len(linhas),
        "n_locais": len(locais),
        "n_segmentos": len(segmentos),
        "linhas": [
            {
                "id_linha": L["id_linha"],
                "route_id": L["route_id"],
                "codigo": L["codigo"],
                "shape_id": L["shape_id"],
                "operadora": L["operadora"],
            }
            for L in linhas
        ],
        "segmentos_osm_way_ids": [s["osm_way_id"] for s in segmentos],
        "n_sensores": 10,
        "n_leituras_trafego": 59,
        "sensor_leitura_source": "fontes/olhovivo/leitura_trafego_real.sql",
        "sources": {
            "gtfs": GTFS_OFFICIAL_NOTE,
            "osm": "https://www.openstreetmap.org/copyright (ODbL 1.0)",
            "olhovivo": {
                "api": "https://api.olhovivo.sptrans.com.br/v2.1",
                "endpoint": "GET /Posicao",
                "window_america_sao_paulo": "2026-11-19 08:33–09:17",
                "token_env": "SPTRANS_OLHOVIVO_TOKEN",
                "sql": "fontes/olhovivo/leitura_trafego_real.sql",
                "method": "fontes/olhovivo/METODO.md",
                "notes": "velocidade de ônibus (com paradas); volume=nº ônibus; nivel derivado; sensores 9–10 inativos (Marginal)",
            },
        },
    }
    (CACHE / "seed_provenance.json").write_text(
        json.dumps(prov, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(
        f"Gerado: {OUT_SQL} | linhas={len(linhas)} locais={len(locais)} segmentos={len(segmentos)}",
        file=sys.stderr,
    )
    return "\n".join(lines_out) + "\n"


def main() -> int:
    sql = build_seed()
    OUT_SQL.parent.mkdir(parents=True, exist_ok=True)
    OUT_SQL.write_text(sql, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
