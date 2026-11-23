-- =============================================================================
-- 05_security.sql – Roles, usuários e GRANTs (menor privilégio)
-- Senhas apenas para ambiente acadêmico/local — trocar em produção.
-- =============================================================================

USE mobilidade_urbana;

-- Roles (idempotente via DROP/CREATE)
DROP ROLE IF EXISTS 'role_app';
DROP ROLE IF EXISTS 'role_analista';
DROP ROLE IF EXISTS 'role_admin_dados';

CREATE ROLE 'role_app';
CREATE ROLE 'role_analista';
CREATE ROLE 'role_admin_dados';

-- Aplicação: CRUD operacional nas tabelas de negócio; EXECUTE em procedures
GRANT SELECT, INSERT, UPDATE, DELETE ON mobilidade_urbana.usuario TO 'role_app';
GRANT SELECT ON mobilidade_urbana.modal_transporte TO 'role_app';
GRANT SELECT ON mobilidade_urbana.fonte_referencia TO 'role_app';
GRANT SELECT ON mobilidade_urbana.fator_emissao TO 'role_app';
GRANT SELECT ON mobilidade_urbana.local TO 'role_app';
GRANT SELECT ON mobilidade_urbana.segmento_via TO 'role_app';
GRANT SELECT ON mobilidade_urbana.sensor TO 'role_app';
GRANT SELECT, INSERT ON mobilidade_urbana.leitura_trafego TO 'role_app';
GRANT SELECT ON mobilidade_urbana.linha_transporte TO 'role_app';
GRANT SELECT, INSERT, UPDATE ON mobilidade_urbana.viagem TO 'role_app';
GRANT SELECT, INSERT, UPDATE, DELETE ON mobilidade_urbana.trecho_viagem TO 'role_app';
GRANT SELECT, INSERT, DELETE ON mobilidade_urbana.trecho_segmento TO 'role_app';
GRANT SELECT, INSERT, UPDATE ON mobilidade_urbana.sugestao_modal TO 'role_app';

GRANT SELECT ON mobilidade_urbana.vw_emissao_trecho TO 'role_app';
GRANT SELECT ON mobilidade_urbana.vw_emissao_viagem TO 'role_app';
GRANT SELECT ON mobilidade_urbana.vw_emissao_usuario TO 'role_app';
GRANT SELECT ON mobilidade_urbana.vw_emissao_modal TO 'role_app';
GRANT SELECT ON mobilidade_urbana.vw_emissao_linha TO 'role_app';
GRANT SELECT ON mobilidade_urbana.vw_economia_vs_carro TO 'role_app';
GRANT SELECT ON mobilidade_urbana.vw_economia_usuario_mes TO 'role_app';
GRANT SELECT ON mobilidade_urbana.vw_congestionamento_atual TO 'role_app';
GRANT SELECT ON mobilidade_urbana.vw_taxa_aceitacao_sugestao TO 'role_app';

GRANT EXECUTE ON PROCEDURE mobilidade_urbana.sp_registrar_viagem TO 'role_app';
GRANT EXECUTE ON PROCEDURE mobilidade_urbana.sp_gerar_sugestao_sustentavel TO 'role_app';
GRANT EXECUTE ON FUNCTION mobilidade_urbana.fn_fator_vigente TO 'role_app';
GRANT EXECUTE ON FUNCTION mobilidade_urbana.fn_co2_estimado_g TO 'role_app';

-- Analista: somente leitura (tabelas + views)
GRANT SELECT ON mobilidade_urbana.* TO 'role_analista';

-- Admin de dados: DDL/DML completo no schema + procedures de manutenção
GRANT ALL PRIVILEGES ON mobilidade_urbana.* TO 'role_admin_dados';
GRANT EXECUTE ON PROCEDURE mobilidade_urbana.sp_limpar_leituras_antigas TO 'role_admin_dados';
GRANT EVENT ON mobilidade_urbana.* TO 'role_admin_dados';

-- Usuários de exemplo (localhost e % para Docker)
DROP USER IF EXISTS 'app_mobilidade'@'localhost';
DROP USER IF EXISTS 'app_mobilidade'@'%';
DROP USER IF EXISTS 'analista_mobilidade'@'localhost';
DROP USER IF EXISTS 'analista_mobilidade'@'%';
DROP USER IF EXISTS 'admin_mobilidade'@'localhost';
DROP USER IF EXISTS 'admin_mobilidade'@'%';

CREATE USER 'app_mobilidade'@'localhost' IDENTIFIED BY 'App#Mob2026';
CREATE USER 'app_mobilidade'@'%'         IDENTIFIED BY 'App#Mob2026';
CREATE USER 'analista_mobilidade'@'localhost' IDENTIFIED BY 'Analista#Mob2026';
CREATE USER 'analista_mobilidade'@'%'         IDENTIFIED BY 'Analista#Mob2026';
CREATE USER 'admin_mobilidade'@'localhost' IDENTIFIED BY 'Admin#Mob2026';
CREATE USER 'admin_mobilidade'@'%'         IDENTIFIED BY 'Admin#Mob2026';

GRANT 'role_app' TO 'app_mobilidade'@'localhost', 'app_mobilidade'@'%';
GRANT 'role_analista' TO 'analista_mobilidade'@'localhost', 'analista_mobilidade'@'%';
GRANT 'role_admin_dados' TO 'admin_mobilidade'@'localhost', 'admin_mobilidade'@'%';

SET DEFAULT ROLE 'role_app' TO 'app_mobilidade'@'localhost', 'app_mobilidade'@'%';
SET DEFAULT ROLE 'role_analista' TO 'analista_mobilidade'@'localhost', 'analista_mobilidade'@'%';
SET DEFAULT ROLE 'role_admin_dados' TO 'admin_mobilidade'@'localhost', 'admin_mobilidade'@'%';

FLUSH PRIVILEGES;
