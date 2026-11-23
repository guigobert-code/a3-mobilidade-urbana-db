-- =============================================================================
-- 09_monitoramento.sql – Consultas de monitoramento (performance_schema / sys)
-- Não faz parte do modelo de 13 tabelas; uso administrativo.
-- =============================================================================

SELECT '=== Versão e uptime ===' AS info;
SELECT VERSION() AS versao, @@hostname AS host,
       ROUND(VARIABLE_VALUE/3600, 2) AS uptime_horas
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Uptime';

SELECT '=== Tabelas do schema (tamanho) ===' AS info;
SELECT table_name, engine, table_rows,
       ROUND(data_length/1024/1024, 3) AS data_mb,
       ROUND(index_length/1024/1024, 3) AS index_mb
FROM information_schema.tables
WHERE table_schema = 'mobilidade_urbana'
ORDER BY (data_length + index_length) DESC;

SELECT '=== Índices espaciais ===' AS info;
SELECT table_name, index_name, index_type, column_name
FROM information_schema.statistics
WHERE table_schema = 'mobilidade_urbana' AND index_type = 'SPATIAL'
ORDER BY table_name;

SELECT '=== Eventos agendados ===' AS info;
SELECT event_schema, event_name, status, interval_value, interval_field, last_executed
FROM information_schema.events
WHERE event_schema = 'mobilidade_urbana';

-- sys schema (quando disponível)
SELECT '=== sys.statements_with_full_table_scans (top) ===' AS info;
SELECT *
FROM sys.statements_with_full_table_scans
WHERE db = 'mobilidade_urbana'
LIMIT 10;

SELECT '=== Threads conectadas ===' AS info;
SELECT processlist_user, processlist_host, processlist_db, processlist_command, processlist_state
FROM performance_schema.threads
WHERE type = 'FOREGROUND' AND processlist_id IS NOT NULL
LIMIT 20;

SELECT '=== InnoDB buffer pool ===' AS info;
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME IN (
  'Innodb_buffer_pool_reads',
  'Innodb_buffer_pool_read_requests',
  'Innodb_row_lock_waits',
  'Questions'
);
