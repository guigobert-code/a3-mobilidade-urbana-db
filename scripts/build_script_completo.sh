#!/usr/bin/env bash
# Gera sql/script_completo.sql a partir dos scripts numerados (fonte da verdade).
# Uso: ./scripts/build_script_completo.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/sql/script_completo.sql"
SQL_DIR="$ROOT/sql"

FILES=(
  "01_schema.sql"
  "02_views.sql"
  "03_triggers.sql"
  "04_procedures.sql"
  "05_security.sql"
  "06_seed.sql"
  "07_relatorios.sql"
  "08_testes.sql"
)

{
  cat <<'HDR'
-- =============================================================================
-- script_completo.sql – GERADO AUTOMATICAMENTE
-- NÃO edite à mão. Fonte da verdade: sql/01_*.sql … sql/08_*.sql
-- Regenerar: ./scripts/build_script_completo.sh
-- Executa do zero: DROP/CREATE DATABASE → schema → views → triggers →
-- procedures/events → roles → seed → relatórios → testes
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

DROP DATABASE IF EXISTS mobilidade_urbana;

HDR

  for f in "${FILES[@]}"; do
    echo ""
    echo "-- ##########################################################################"
    echo "-- INÍCIO: $f"
    echo "-- ##########################################################################"
    echo ""
    # Remove o DROP DATABASE se algum dia existir nos numerados; 01 faz CREATE IF NOT EXISTS
    cat "$SQL_DIR/$f"
    echo ""
    echo "-- ### FIM: $f ###"
    echo ""
  done
} > "$OUT"

echo "Gerado: $OUT ($(wc -l < "$OUT") linhas)"
