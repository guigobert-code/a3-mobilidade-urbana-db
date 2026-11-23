#!/usr/bin/env python3
"""Coleta posições de todos os ônibus (GET /Posicao) da API Olho Vivo v2.1 (SPTrans).
Token lido da variável de ambiente SPTRANS_OLHOVIVO_TOKEN (nunca gravado em arquivo).
Uso: python3 coletar_posicoes.py [duracao_min=20] [intervalo_s=30] [saida=raw]
"""
import os, sys, time, json, datetime, http.cookiejar, urllib.request, urllib.error, gzip, signal
from zoneinfo import ZoneInfo

BASE = "https://api.olhovivo.sptrans.com.br/v2.1"
TZ = ZoneInfo("America/Sao_Paulo")
dur = float(sys.argv[1]) if len(sys.argv) > 1 else 20
intv = float(sys.argv[2]) if len(sys.argv) > 2 else 30
out = sys.argv[3] if len(sys.argv) > 3 else "raw"
os.makedirs(out, exist_ok=True)

token = os.environ["SPTRANS_OLHOVIVO_TOKEN"].strip()
jar = http.cookiejar.CookieJar()
op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
op.addheaders = [("User-Agent", "curl/8.5.0"), ("Accept", "application/json")]

def auth():
    req = urllib.request.Request(f"{BASE}/Login/Autenticar?token={token}", data=b"", method="POST", headers={"Content-Length": "0"})
    ok = op.open(req, timeout=30).read().decode().strip()
    print("auth:", ok, flush=True)
    return ok == "true"

def _alarme(signum, frame):
    raise TimeoutError("requisição excedeu 90 s")
signal.signal(signal.SIGALRM, _alarme)

auth()
fim = time.time() + dur * 60
n = 0
while time.time() < fim:
    t0 = time.time()
    signal.alarm(90)   # teto duro por ciclo (o timeout do socket não cobre leitura lenta)
    try:
        try:
            body = op.open(f"{BASE}/Posicao", timeout=60).read()
        except urllib.error.HTTPError as e:
            if e.code == 401:
                auth(); body = op.open(f"{BASE}/Posicao", timeout=60).read()
            else:
                raise
        ts = datetime.datetime.now(TZ).strftime("%Y%m%dT%H%M%S%z")
        with gzip.open(f"{out}/posicao_{ts}.json.gz", "wb") as f:
            f.write(body)
        d = json.loads(body)
        if not isinstance(d, dict):   # resposta "null": sessão/servidor instável -> reautentica
            print(ts, "resposta null; reautenticando", flush=True); auth(); continue
        n += 1
        print(ts, "linhas", len(d.get("l", [])), "veiculos", sum(len(l["vs"]) for l in d.get("l", [])), flush=True)
    except Exception as e:
        print("erro:", repr(e), flush=True)
    finally:
        signal.alarm(0)
    time.sleep(max(0, intv - (time.time() - t0)))
print("snapshots:", n)
