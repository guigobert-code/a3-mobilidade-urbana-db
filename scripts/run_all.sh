#!/usr/bin/env bash
# Executa os scripts numerados em ordem contra MySQL 8.
# Variáveis: MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PWD MYSQL_OPTS
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${MYSQL_HOST:-127.0.0.1}"
PORT="${MYSQL_PORT:-3306}"
USER="${MYSQL_USER:-root}"
export MYSQL_PWD="${MYSQL_PWD:-rootpass}"

MYSQL=(mysql -h"$HOST" -P"$PORT" -u"$USER" --default-character-set=utf8mb4 --comments)

echo "==> MySQL target: $USER@$HOST:$PORT"
"${MYSQL[@]}" -e "SELECT VERSION() AS versao;"

for f in \
  01_schema.sql \
  02_views.sql \
  03_triggers.sql \
  04_procedures.sql \
  05_security.sql \
  06_seed.sql \
  07_relatorios.sql \
  08_testes.sql
do
  echo ""
  echo "==> Executando sql/$f"
  "${MYSQL[@]}" < "$ROOT/sql/$f"
done

echo ""
echo "==> Concluído (scripts numerados)."
