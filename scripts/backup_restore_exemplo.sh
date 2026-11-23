#!/usr/bin/env bash
# Exemplo de backup lógico (mysqldump) + notas de point-in-time via binlog.
# Ambiente acadêmico local — ajuste caminhos/credenciais em produção.
set -euo pipefail

HOST="${MYSQL_HOST:-127.0.0.1}"
PORT="${MYSQL_PORT:-3306}"
USER="${MYSQL_USER:-root}"
export MYSQL_PWD="${MYSQL_PWD:-rootpass}"
DB="${MYSQL_DATABASE:-mobilidade_urbana}"
OUT_DIR="${BACKUP_DIR:-./backups}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
DUMP="$OUT_DIR/${DB}_${TS}.sql"

mkdir -p "$OUT_DIR"

echo "==> Dump lógico de $DB → $DUMP"
mysqldump -h"$HOST" -P"$PORT" -u"$USER" \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --set-gtid-purged=OFF \
  --default-character-set=utf8mb4 \
  "$DB" > "$DUMP"

# Posição do binlog no momento do dump (útil para PITR)
echo "==> Posição atual do binlog (anotar para point-in-time recovery):"
mysql -h"$HOST" -P"$PORT" -u"$USER" -e "SHOW MASTER STATUS\G" || \
mysql -h"$HOST" -P"$PORT" -u"$USER" -e "SHOW BINARY LOG STATUS\G" || true

cat <<'NOTAS'

-----------------------------------------------------------------------------
Point-in-Time Recovery (resumo):
1) Restaurar o dump até um instante base:
     mysql -uroot -p mobilidade_urbana < backups/mobilidade_urbana_YYYYMMDD.sql
2) Aplicar eventos do binlog DEPOIS da posição capturada no SHOW MASTER STATUS
   até o horário desejado (--stop-datetime):
     mysqlbinlog --start-position=POS mysql-bin.00000N \
       --stop-datetime="2026-11-18 15:30:00" | mysql -uroot -p
3) Exige log-bin habilitado (ver docker-compose.yml / my.cnf).
-----------------------------------------------------------------------------
Restore completo a partir deste dump:
  mysql -h127.0.0.1 -uroot -p -e "DROP DATABASE IF EXISTS mobilidade_urbana; CREATE DATABASE mobilidade_urbana CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
  mysql -h127.0.0.1 -uroot -p mobilidade_urbana < "$DUMP"

NOTAS

echo "==> Backup salvo em $DUMP ($(wc -c < "$DUMP") bytes)"
