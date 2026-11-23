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


-- ##########################################################################
-- INÍCIO: 01_schema.sql
-- ##########################################################################

-- =============================================================================
-- 01_schema.sql – Banco, tabelas, PK/FK/UNIQUE/CHECK e índices (idempotente)
-- Projeto A3 – Mobilidade Urbana Sustentável – MySQL 8.0 / InnoDB / utf8mb4
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE DATABASE IF NOT EXISTS mobilidade_urbana
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE mobilidade_urbana;

-- Ordem de drop respeitando FKs (reexecução limpa)
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS sugestao_modal;
DROP TABLE IF EXISTS trecho_segmento;
DROP TABLE IF EXISTS trecho_viagem;
DROP TABLE IF EXISTS viagem;
DROP TABLE IF EXISTS leitura_trafego;
DROP TABLE IF EXISTS sensor;
DROP TABLE IF EXISTS linha_transporte;
DROP TABLE IF EXISTS segmento_via;
DROP TABLE IF EXISTS local;
DROP TABLE IF EXISTS fator_emissao;
DROP TABLE IF EXISTS fonte_referencia;
DROP TABLE IF EXISTS usuario;
DROP TABLE IF EXISTS modal_transporte;
SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- modal_transporte
-- -----------------------------------------------------------------------------
CREATE TABLE modal_transporte (
  id_modal              SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo                VARCHAR(20)  NOT NULL,
  nome                  VARCHAR(60)  NOT NULL,
  categoria             ENUM('ativo','coletivo','individual') NOT NULL,
  sustentavel           BOOLEAN      NOT NULL,
  referencia_comparacao BOOLEAN      NOT NULL DEFAULT FALSE,
  ref_unica             TINYINT
    GENERATED ALWAYS AS (IF(referencia_comparacao, 1, NULL)) STORED,
  PRIMARY KEY (id_modal),
  UNIQUE KEY uk_modal_codigo (codigo),
  UNIQUE KEY uk_modal_ref_unica (ref_unica)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- usuario
-- -----------------------------------------------------------------------------
CREATE TABLE usuario (
  id_usuario         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome               VARCHAR(120) NOT NULL,
  email              VARCHAR(254) NOT NULL,
  cpf_hash           CHAR(64)     NULL,
  data_nascimento    DATE         NULL,
  id_modal_preferido SMALLINT UNSIGNED NULL,
  criado_em          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ativo              BOOLEAN      NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id_usuario),
  UNIQUE KEY uk_usuario_email (email),
  UNIQUE KEY uk_usuario_cpf_hash (cpf_hash),
  CONSTRAINT fk_usuario_modal
    FOREIGN KEY (id_modal_preferido) REFERENCES modal_transporte (id_modal)
    ON DELETE SET NULL
    ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- fonte_referencia
-- -----------------------------------------------------------------------------
CREATE TABLE fonte_referencia (
  id_fonte         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  orgao            VARCHAR(80)  NOT NULL,
  titulo           VARCHAR(250) NOT NULL,
  ano_publicacao   SMALLINT UNSIGNED NOT NULL,
  url              VARCHAR(500) NOT NULL,
  PRIMARY KEY (id_fonte),
  CONSTRAINT chk_fonte_ano
    CHECK (ano_publicacao BETWEEN 1990 AND 2100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- fator_emissao
-- id_fonte SEM ação referencial (participa de CHECK)
-- -----------------------------------------------------------------------------
CREATE TABLE fator_emissao (
  id_fator         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_modal         SMALLINT UNSIGNED NOT NULL,
  id_fonte         INT UNSIGNED NULL,
  g_co2_pkm        DECIMAL(8,3) NOT NULL,
  estimativa       BOOLEAN NOT NULL,
  vigencia_inicio  DATE NOT NULL,
  vigencia_fim     DATE NULL,
  PRIMARY KEY (id_fator),
  KEY idx_fator_modal_inicio (id_modal, vigencia_inicio),
  CONSTRAINT fk_fator_modal
    FOREIGN KEY (id_modal) REFERENCES modal_transporte (id_modal)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT fk_fator_fonte
    FOREIGN KEY (id_fonte) REFERENCES fonte_referencia (id_fonte),
  CONSTRAINT chk_fator_g_co2
    CHECK (g_co2_pkm >= 0),
  CONSTRAINT chk_fator_estimativa_fonte
    CHECK (estimativa OR id_fonte IS NOT NULL),
  CONSTRAINT chk_fator_vigencia
    CHECK (vigencia_fim IS NULL OR vigencia_fim > vigencia_inicio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- local (SRID 4326 + índice espacial)
-- -----------------------------------------------------------------------------
CREATE TABLE local (
  id_local BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome     VARCHAR(150) NOT NULL,
  tipo     ENUM('estacao','ponto_onibus','endereco') NOT NULL,
  geom     POINT SRID 4326 NOT NULL,
  PRIMARY KEY (id_local),
  SPATIAL KEY spx_local_geom (geom)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- segmento_via
-- -----------------------------------------------------------------------------
CREATE TABLE segmento_via (
  id_segmento         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome_via            VARCHAR(150) NOT NULL,
  geom                LINESTRING SRID 4326 NOT NULL,
  velocidade_max_kmh  SMALLINT UNSIGNED NOT NULL,
  possui_ciclovia     BOOLEAN NOT NULL,
  faixa_onibus        BOOLEAN NOT NULL,
  PRIMARY KEY (id_segmento),
  SPATIAL KEY spx_segmento_geom (geom),
  CONSTRAINT chk_segmento_vel
    CHECK (velocidade_max_kmh > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- sensor
-- -----------------------------------------------------------------------------
CREATE TABLE sensor (
  id_sensor     INT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_segmento   BIGINT UNSIGNED NOT NULL,
  tipo          ENUM('laco','camera','gps_frota') NOT NULL,
  geom          POINT SRID 4326 NOT NULL,
  instalado_em  DATE NOT NULL,
  status        ENUM('ativo','manutencao','inativo') NOT NULL DEFAULT 'ativo',
  PRIMARY KEY (id_sensor),
  KEY idx_sensor_segmento (id_segmento),
  SPATIAL KEY spx_sensor_geom (geom),
  CONSTRAINT fk_sensor_segmento
    FOREIGN KEY (id_segmento) REFERENCES segmento_via (id_segmento)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- leitura_trafego (NÃO particionada — mantém FK)
-- -----------------------------------------------------------------------------
CREATE TABLE leitura_trafego (
  id_leitura              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_sensor               INT UNSIGNED NOT NULL,
  registrado_em           DATETIME(3) NOT NULL,
  velocidade_media_kmh    DECIMAL(5,1) NULL,
  volume_veiculos         INT UNSIGNED NULL,
  nivel_congestionamento  TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (id_leitura),
  UNIQUE KEY uk_leitura_sensor_ts (id_sensor, registrado_em),
  KEY idx_leitura_registrado_em (registrado_em),
  CONSTRAINT fk_leitura_sensor
    FOREIGN KEY (id_sensor) REFERENCES sensor (id_sensor)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT chk_leitura_vel
    CHECK (velocidade_media_kmh IS NULL OR velocidade_media_kmh >= 0),
  CONSTRAINT chk_leitura_nivel
    CHECK (nivel_congestionamento BETWEEN 0 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- linha_transporte
-- -----------------------------------------------------------------------------
CREATE TABLE linha_transporte (
  id_linha      INT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_modal      SMALLINT UNSIGNED NOT NULL,
  codigo        VARCHAR(20)  NOT NULL,
  nome          VARCHAR(150) NOT NULL,
  operadora     VARCHAR(100) NULL,
  geom_trajeto  LINESTRING SRID 4326 NOT NULL,
  PRIMARY KEY (id_linha),
  UNIQUE KEY uk_linha_codigo (codigo),
  KEY idx_linha_modal (id_modal),
  SPATIAL KEY spx_linha_trajeto (geom_trajeto),
  CONSTRAINT fk_linha_modal
    FOREIGN KEY (id_modal) REFERENCES modal_transporte (id_modal)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- viagem
-- locais SEM ação referencial (CHECK destino <> origem)
-- -----------------------------------------------------------------------------
CREATE TABLE viagem (
  id_viagem         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_usuario        BIGINT UNSIGNED NOT NULL,
  id_local_origem   BIGINT UNSIGNED NOT NULL,
  id_local_destino  BIGINT UNSIGNED NOT NULL,
  inicio            DATETIME NOT NULL,
  fim               DATETIME NULL,
  status            ENUM('planejada','em_curso','concluida','cancelada')
                    NOT NULL DEFAULT 'planejada',
  PRIMARY KEY (id_viagem),
  KEY idx_viagem_usuario_inicio (id_usuario, inicio),
  KEY idx_viagem_origem (id_local_origem),
  KEY idx_viagem_destino (id_local_destino),
  CONSTRAINT fk_viagem_usuario
    FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT fk_viagem_origem
    FOREIGN KEY (id_local_origem) REFERENCES local (id_local),
  CONSTRAINT fk_viagem_destino
    FOREIGN KEY (id_local_destino) REFERENCES local (id_local),
  CONSTRAINT chk_viagem_destino_diff
    CHECK (id_local_destino <> id_local_origem),
  CONSTRAINT chk_viagem_fim
    CHECK (fim IS NULL OR fim > inicio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- trecho_viagem
-- -----------------------------------------------------------------------------
CREATE TABLE trecho_viagem (
  id_trecho      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_viagem      BIGINT UNSIGNED NOT NULL,
  ordem          TINYINT UNSIGNED NOT NULL,
  id_modal       SMALLINT UNSIGNED NOT NULL,
  id_linha       INT UNSIGNED NULL,
  inicio         DATETIME NOT NULL,
  fim            DATETIME NOT NULL,
  distancia_km   DECIMAL(7,3) NOT NULL,
  geom_percurso  LINESTRING SRID 4326 NULL,
  PRIMARY KEY (id_trecho),
  UNIQUE KEY uk_trecho_viagem_ordem (id_viagem, ordem),
  KEY idx_trecho_modal (id_modal),
  KEY idx_trecho_linha (id_linha),
  CONSTRAINT fk_trecho_viagem
    FOREIGN KEY (id_viagem) REFERENCES viagem (id_viagem)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_trecho_modal
    FOREIGN KEY (id_modal) REFERENCES modal_transporte (id_modal)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT fk_trecho_linha
    FOREIGN KEY (id_linha) REFERENCES linha_transporte (id_linha)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT chk_trecho_fim
    CHECK (fim > inicio),
  CONSTRAINT chk_trecho_dist
    CHECK (distancia_km > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- trecho_segmento (N:N)
-- -----------------------------------------------------------------------------
CREATE TABLE trecho_segmento (
  id_trecho    BIGINT UNSIGNED NOT NULL,
  id_segmento  BIGINT UNSIGNED NOT NULL,
  ordem        SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (id_trecho, id_segmento),
  KEY idx_ts_segmento (id_segmento),
  CONSTRAINT fk_ts_trecho
    FOREIGN KEY (id_trecho) REFERENCES trecho_viagem (id_trecho)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_ts_segmento
    FOREIGN KEY (id_segmento) REFERENCES segmento_via (id_segmento)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- -----------------------------------------------------------------------------
-- sugestao_modal
-- -----------------------------------------------------------------------------
CREATE TABLE sugestao_modal (
  id_sugestao             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_viagem               BIGINT UNSIGNED NOT NULL,
  id_modal_sugerido       SMALLINT UNSIGNED NOT NULL,
  id_linha                INT UNSIGNED NULL,
  distancia_estimada_km   DECIMAL(7,3) NOT NULL,
  duracao_estimada_min    SMALLINT UNSIGNED NOT NULL,
  motivo                  ENUM('congestionamento','menor_co2','menor_tempo') NOT NULL,
  gerada_em               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  aceita                  BOOLEAN NULL,
  PRIMARY KEY (id_sugestao),
  KEY idx_sugestao_viagem (id_viagem),
  KEY idx_sugestao_modal (id_modal_sugerido),
  KEY idx_sugestao_linha (id_linha),
  CONSTRAINT fk_sugestao_viagem
    FOREIGN KEY (id_viagem) REFERENCES viagem (id_viagem)
    ON DELETE CASCADE
    ON UPDATE RESTRICT,
  CONSTRAINT fk_sugestao_modal
    FOREIGN KEY (id_modal_sugerido) REFERENCES modal_transporte (id_modal)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT fk_sugestao_linha
    FOREIGN KEY (id_linha) REFERENCES linha_transporte (id_linha)
    ON DELETE RESTRICT
    ON UPDATE RESTRICT,
  CONSTRAINT chk_sugestao_dist
    CHECK (distancia_estimada_km > 0),
  CONSTRAINT chk_sugestao_duracao
    CHECK (duracao_estimada_min > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ### FIM: 01_schema.sql ###


-- ##########################################################################
-- INÍCIO: 02_views.sql
-- ##########################################################################

-- =============================================================================
-- 02_views.sql – Views de emissão de CO₂, economia vs carro e congestionamento
-- Fator vigente na data do trecho (DATE(trecho.inicio))
-- =============================================================================

USE mobilidade_urbana;

DROP VIEW IF EXISTS vw_emissao_trecho;
DROP VIEW IF EXISTS vw_emissao_viagem;
DROP VIEW IF EXISTS vw_emissao_usuario;
DROP VIEW IF EXISTS vw_emissao_modal;
DROP VIEW IF EXISTS vw_emissao_linha;
DROP VIEW IF EXISTS vw_economia_vs_carro;
DROP VIEW IF EXISTS vw_economia_usuario_mes;
DROP VIEW IF EXISTS vw_congestionamento_atual;
DROP VIEW IF EXISTS vw_taxa_aceitacao_sugestao;

-- CO₂ por trecho: distancia_km × fator vigente na data do trecho
CREATE OR REPLACE VIEW vw_emissao_trecho AS
SELECT
  t.id_trecho,
  t.id_viagem,
  t.ordem,
  t.id_modal,
  m.codigo AS codigo_modal,
  m.nome   AS nome_modal,
  t.id_linha,
  l.codigo AS codigo_linha,
  t.inicio,
  t.fim,
  t.distancia_km,
  f.id_fator,
  f.g_co2_pkm,
  ROUND(t.distancia_km * f.g_co2_pkm, 3) AS co2_trecho_g
FROM trecho_viagem t
JOIN modal_transporte m ON m.id_modal = t.id_modal
LEFT JOIN linha_transporte l ON l.id_linha = t.id_linha
JOIN fator_emissao f
  ON f.id_modal = t.id_modal
 AND f.vigencia_inicio <= DATE(t.inicio)
 AND (f.vigencia_fim IS NULL OR f.vigencia_fim > DATE(t.inicio));

-- CO₂ por viagem
CREATE OR REPLACE VIEW vw_emissao_viagem AS
SELECT
  v.id_viagem,
  v.id_usuario,
  u.nome AS nome_usuario,
  v.inicio,
  v.fim,
  v.status,
  COUNT(e.id_trecho) AS qtd_trechos,
  ROUND(SUM(e.distancia_km), 3) AS distancia_total_km,
  ROUND(SUM(e.co2_trecho_g), 3) AS co2_viagem_g
FROM viagem v
JOIN usuario u ON u.id_usuario = v.id_usuario
LEFT JOIN vw_emissao_trecho e ON e.id_viagem = v.id_viagem
GROUP BY v.id_viagem, v.id_usuario, u.nome, v.inicio, v.fim, v.status;

-- CO₂ por usuário (agregado)
CREATE OR REPLACE VIEW vw_emissao_usuario AS
SELECT
  u.id_usuario,
  u.nome,
  u.email,
  COUNT(DISTINCT ev.id_viagem) AS qtd_viagens,
  ROUND(COALESCE(SUM(ev.distancia_total_km), 0), 3) AS distancia_total_km,
  ROUND(COALESCE(SUM(ev.co2_viagem_g), 0), 3) AS co2_total_g
FROM usuario u
LEFT JOIN vw_emissao_viagem ev
  ON ev.id_usuario = u.id_usuario
 AND ev.status = 'concluida'
GROUP BY u.id_usuario, u.nome, u.email;

-- CO₂ por modal
CREATE OR REPLACE VIEW vw_emissao_modal AS
SELECT
  m.id_modal,
  m.codigo,
  m.nome,
  m.categoria,
  COUNT(e.id_trecho) AS qtd_trechos,
  ROUND(COALESCE(SUM(e.distancia_km), 0), 3) AS distancia_total_km,
  ROUND(COALESCE(SUM(e.co2_trecho_g), 0), 3) AS co2_total_g
FROM modal_transporte m
LEFT JOIN vw_emissao_trecho e ON e.id_modal = m.id_modal
GROUP BY m.id_modal, m.codigo, m.nome, m.categoria;

-- CO₂ por linha / rota
CREATE OR REPLACE VIEW vw_emissao_linha AS
SELECT
  l.id_linha,
  l.codigo,
  l.nome,
  l.operadora,
  m.codigo AS codigo_modal,
  COUNT(e.id_trecho) AS qtd_trechos,
  ROUND(COALESCE(SUM(e.distancia_km), 0), 3) AS distancia_total_km,
  ROUND(COALESCE(SUM(e.co2_trecho_g), 0), 3) AS co2_total_g
FROM linha_transporte l
JOIN modal_transporte m ON m.id_modal = l.id_modal
LEFT JOIN vw_emissao_trecho e ON e.id_linha = l.id_linha
GROUP BY l.id_linha, l.codigo, l.nome, l.operadora, m.codigo;

-- Economia vs carro: mesma distância × (fator_carro − fator_modal)
CREATE OR REPLACE VIEW vw_economia_vs_carro AS
SELECT
  e.id_trecho,
  e.id_viagem,
  e.id_modal,
  e.codigo_modal,
  e.distancia_km,
  e.g_co2_pkm AS fator_modal_g,
  fc.g_co2_pkm AS fator_carro_g,
  e.co2_trecho_g,
  ROUND(e.distancia_km * fc.g_co2_pkm, 3) AS co2_se_carro_g,
  ROUND(e.distancia_km * (fc.g_co2_pkm - e.g_co2_pkm), 3) AS economia_vs_carro_g
FROM vw_emissao_trecho e
JOIN modal_transporte mc ON mc.referencia_comparacao = TRUE
JOIN fator_emissao fc
  ON fc.id_modal = mc.id_modal
 AND fc.vigencia_inicio <= DATE(e.inicio)
 AND (fc.vigencia_fim IS NULL OR fc.vigencia_fim > DATE(e.inicio));

-- Economia mensal por usuário
CREATE OR REPLACE VIEW vw_economia_usuario_mes AS
SELECT
  v.id_usuario,
  u.nome AS nome_usuario,
  DATE_FORMAT(v.inicio, '%Y-%m') AS ano_mes,
  COUNT(DISTINCT v.id_viagem) AS qtd_viagens,
  ROUND(SUM(ec.distancia_km), 3) AS distancia_km,
  ROUND(SUM(ec.co2_trecho_g), 3) AS co2_emitido_g,
  ROUND(SUM(ec.co2_se_carro_g), 3) AS co2_se_carro_g,
  ROUND(SUM(ec.economia_vs_carro_g), 3) AS economia_vs_carro_g
FROM viagem v
JOIN usuario u ON u.id_usuario = v.id_usuario
JOIN vw_economia_vs_carro ec ON ec.id_viagem = v.id_viagem
WHERE v.status = 'concluida'
GROUP BY v.id_usuario, u.nome, DATE_FORMAT(v.inicio, '%Y-%m');

-- Última leitura de congestionamento por segmento
CREATE OR REPLACE VIEW vw_congestionamento_atual AS
SELECT
  s.id_segmento,
  s.nome_via,
  s.velocidade_max_kmh,
  s.possui_ciclovia,
  s.faixa_onibus,
  sens.id_sensor,
  sens.tipo AS tipo_sensor,
  lt.registrado_em,
  lt.velocidade_media_kmh,
  lt.volume_veiculos,
  lt.nivel_congestionamento
FROM segmento_via s
JOIN sensor sens ON sens.id_segmento = s.id_segmento AND sens.status = 'ativo'
JOIN leitura_trafego lt ON lt.id_sensor = sens.id_sensor
JOIN (
  SELECT lt2.id_sensor, MAX(lt2.registrado_em) AS max_ts
  FROM leitura_trafego lt2
  GROUP BY lt2.id_sensor
) ult ON ult.id_sensor = lt.id_sensor AND ult.max_ts = lt.registrado_em;

-- Taxa de aceitação de sugestões
CREATE OR REPLACE VIEW vw_taxa_aceitacao_sugestao AS
SELECT
  COUNT(*) AS total_sugestoes,
  SUM(CASE WHEN aceita = TRUE  THEN 1 ELSE 0 END) AS aceitas,
  SUM(CASE WHEN aceita = FALSE THEN 1 ELSE 0 END) AS recusadas,
  SUM(CASE WHEN aceita IS NULL THEN 1 ELSE 0 END) AS sem_resposta,
  ROUND(
    100 * SUM(CASE WHEN aceita = TRUE THEN 1 ELSE 0 END)
      / NULLIF(SUM(CASE WHEN aceita IS NOT NULL THEN 1 ELSE 0 END), 0),
    2
  ) AS taxa_aceitacao_pct
FROM sugestao_modal;

-- ### FIM: 02_views.sql ###


-- ##########################################################################
-- INÍCIO: 03_triggers.sql
-- ##########################################################################

-- =============================================================================
-- 03_triggers.sql – Triggers do modelo + complementares
-- =============================================================================

USE mobilidade_urbana;

DELIMITER $$

-- -----------------------------------------------------------------------------
-- Fator de emissão: bloquear sobreposição de vigência no mesmo modal
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_fator_emissao_sem_sobreposicao_bi$$
CREATE TRIGGER trg_fator_emissao_sem_sobreposicao_bi
BEFORE INSERT ON fator_emissao
FOR EACH ROW
BEGIN
  DECLARE v_conflitos INT DEFAULT 0;
  SELECT COUNT(*) INTO v_conflitos
  FROM fator_emissao f
  WHERE f.id_modal = NEW.id_modal
    AND f.vigencia_inicio < IFNULL(NEW.vigencia_fim, '9999-12-31')
    AND IFNULL(f.vigencia_fim, '9999-12-31') > NEW.vigencia_inicio;
  IF v_conflitos > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Sobreposição de vigência de fator_emissao para o mesmo modal.';
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_fator_emissao_sem_sobreposicao_bu$$
CREATE TRIGGER trg_fator_emissao_sem_sobreposicao_bu
BEFORE UPDATE ON fator_emissao
FOR EACH ROW
BEGIN
  DECLARE v_conflitos INT DEFAULT 0;
  SELECT COUNT(*) INTO v_conflitos
  FROM fator_emissao f
  WHERE f.id_modal = NEW.id_modal
    AND f.id_fator <> NEW.id_fator
    AND f.vigencia_inicio < IFNULL(NEW.vigencia_fim, '9999-12-31')
    AND IFNULL(f.vigencia_fim, '9999-12-31') > NEW.vigencia_inicio;
  IF v_conflitos > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Sobreposição de vigência de fator_emissao para o mesmo modal.';
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- trecho_viagem: modal coerente com linha_transporte
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_trecho_modal_coerente_linha_bi$$
CREATE TRIGGER trg_trecho_modal_coerente_linha_bi
BEFORE INSERT ON trecho_viagem
FOR EACH ROW
BEGIN
  DECLARE v_modal_linha SMALLINT UNSIGNED;
  IF NEW.id_linha IS NOT NULL THEN
    SELECT id_modal INTO v_modal_linha
    FROM linha_transporte
    WHERE id_linha = NEW.id_linha;
    IF v_modal_linha IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Linha informada em trecho_viagem não existe.';
    END IF;
    IF v_modal_linha <> NEW.id_modal THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'id_modal do trecho deve coincidir com id_modal da linha.';
    END IF;
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_trecho_modal_coerente_linha_bu$$
CREATE TRIGGER trg_trecho_modal_coerente_linha_bu
BEFORE UPDATE ON trecho_viagem
FOR EACH ROW
BEGIN
  DECLARE v_modal_linha SMALLINT UNSIGNED;
  IF NEW.id_linha IS NOT NULL THEN
    SELECT id_modal INTO v_modal_linha
    FROM linha_transporte
    WHERE id_linha = NEW.id_linha;
    IF v_modal_linha IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Linha informada em trecho_viagem não existe.';
    END IF;
    IF v_modal_linha <> NEW.id_modal THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'id_modal do trecho deve coincidir com id_modal da linha.';
    END IF;
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- sugestao_modal: modal deve ser sustentável + coerência com linha
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_sugestao_modal_sustentavel_bi$$
CREATE TRIGGER trg_sugestao_modal_sustentavel_bi
BEFORE INSERT ON sugestao_modal
FOR EACH ROW
BEGIN
  DECLARE v_sust BOOLEAN;
  DECLARE v_modal_linha SMALLINT UNSIGNED;
  SELECT sustentavel INTO v_sust
  FROM modal_transporte
  WHERE id_modal = NEW.id_modal_sugerido;
  IF v_sust IS NULL OR v_sust = FALSE THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Só é permitido sugerir modal com sustentavel = TRUE.';
  END IF;
  IF NEW.id_linha IS NOT NULL THEN
    SELECT id_modal INTO v_modal_linha
    FROM linha_transporte
    WHERE id_linha = NEW.id_linha;
    IF v_modal_linha IS NULL OR v_modal_linha <> NEW.id_modal_sugerido THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'id_modal_sugerido deve coincidir com id_modal da linha.';
    END IF;
  END IF;
END$$

DROP TRIGGER IF EXISTS trg_sugestao_modal_sustentavel_bu$$
CREATE TRIGGER trg_sugestao_modal_sustentavel_bu
BEFORE UPDATE ON sugestao_modal
FOR EACH ROW
BEGIN
  DECLARE v_sust BOOLEAN;
  DECLARE v_modal_linha SMALLINT UNSIGNED;
  SELECT sustentavel INTO v_sust
  FROM modal_transporte
  WHERE id_modal = NEW.id_modal_sugerido;
  IF v_sust IS NULL OR v_sust = FALSE THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Só é permitido sugerir modal com sustentavel = TRUE.';
  END IF;
  IF NEW.id_linha IS NOT NULL THEN
    SELECT id_modal INTO v_modal_linha
    FROM linha_transporte
    WHERE id_linha = NEW.id_linha;
    IF v_modal_linha IS NULL OR v_modal_linha <> NEW.id_modal_sugerido THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'id_modal_sugerido deve coincidir com id_modal da linha.';
    END IF;
  END IF;
END$$

-- -----------------------------------------------------------------------------
-- Complementar: viagem concluída exige ao menos um trecho
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_viagem_concluida_tem_trecho_bu$$
CREATE TRIGGER trg_viagem_concluida_tem_trecho_bu
BEFORE UPDATE ON viagem
FOR EACH ROW
BEGIN
  DECLARE v_qtd INT DEFAULT 0;
  IF NEW.status = 'concluida' AND (OLD.status <> 'concluida' OR OLD.status IS NULL) THEN
    SELECT COUNT(*) INTO v_qtd FROM trecho_viagem WHERE id_viagem = NEW.id_viagem;
    IF v_qtd = 0 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Viagem concluída precisa ter ao menos um trecho.';
    END IF;
    IF NEW.fim IS NULL THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Viagem concluída precisa ter fim preenchido.';
    END IF;
  END IF;
END$$

DELIMITER ;

-- ### FIM: 03_triggers.sql ###


-- ##########################################################################
-- INÍCIO: 04_procedures.sql
-- ##########################################################################

-- =============================================================================
-- 04_procedures.sql – Procedures, functions e EVENT de retenção
-- =============================================================================

USE mobilidade_urbana;

DELIMITER $$

-- -----------------------------------------------------------------------------
-- Função: fator vigente (g CO₂e/pkm) para modal em uma data
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_fator_vigente$$
CREATE FUNCTION fn_fator_vigente(p_id_modal SMALLINT UNSIGNED, p_data DATE)
RETURNS DECIMAL(8,3)
READS SQL DATA
DETERMINISTIC
BEGIN
  DECLARE v_fator DECIMAL(8,3);
  SELECT f.g_co2_pkm INTO v_fator
  FROM fator_emissao f
  WHERE f.id_modal = p_id_modal
    AND f.vigencia_inicio <= p_data
    AND (f.vigencia_fim IS NULL OR f.vigencia_fim > p_data)
  ORDER BY f.vigencia_inicio DESC
  LIMIT 1;
  RETURN v_fator;
END$$

-- -----------------------------------------------------------------------------
-- Função: CO₂ estimado (g) para distância × modal na data
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_co2_estimado_g$$
CREATE FUNCTION fn_co2_estimado_g(
  p_id_modal SMALLINT UNSIGNED,
  p_distancia_km DECIMAL(7,3),
  p_data DATE
)
RETURNS DECIMAL(12,3)
READS SQL DATA
DETERMINISTIC
BEGIN
  DECLARE v_fator DECIMAL(8,3);
  SET v_fator = fn_fator_vigente(p_id_modal, p_data);
  IF v_fator IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN ROUND(p_distancia_km * v_fator, 3);
END$$

-- -----------------------------------------------------------------------------
-- Procedure: registrar viagem + trechos em transação (rollback em erro)
-- p_trechos_json: array JSON
--   [{"ordem":1,"id_modal":3,"id_linha":1,"inicio":"...","fim":"...","distancia_km":4.2}, ...]
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_viagem$$
CREATE PROCEDURE sp_registrar_viagem(
  IN  p_id_usuario       BIGINT UNSIGNED,
  IN  p_id_local_origem  BIGINT UNSIGNED,
  IN  p_id_local_destino BIGINT UNSIGNED,
  IN  p_inicio           DATETIME,
  IN  p_fim              DATETIME,
  IN  p_status           VARCHAR(20),
  IN  p_trechos_json     JSON,
  OUT p_id_viagem        BIGINT UNSIGNED,
  OUT p_mensagem         VARCHAR(255)
)
proc_body: BEGIN
  DECLARE v_i INT DEFAULT 0;
  DECLARE v_n INT DEFAULT 0;
  DECLARE v_ordem TINYINT UNSIGNED;
  DECLARE v_id_modal SMALLINT UNSIGNED;
  DECLARE v_id_linha INT UNSIGNED;
  DECLARE v_inicio DATETIME;
  DECLARE v_fim DATETIME;
  DECLARE v_dist DECIMAL(7,3);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 p_mensagem = MESSAGE_TEXT;
    ROLLBACK;
    SET p_id_viagem = NULL;
    IF p_mensagem IS NULL OR p_mensagem = '' THEN
      SET p_mensagem = 'Erro na transação; rollback efetuado.';
    END IF;
  END;

  IF p_trechos_json IS NULL OR JSON_TYPE(p_trechos_json) <> 'ARRAY'
     OR JSON_LENGTH(p_trechos_json) = 0 THEN
    SET p_id_viagem = NULL;
    SET p_mensagem = 'Informe ao menos um trecho no JSON.';
    LEAVE proc_body;
  END IF;

  START TRANSACTION;

  INSERT INTO viagem (
    id_usuario, id_local_origem, id_local_destino, inicio, fim, status
  ) VALUES (
    p_id_usuario, p_id_local_origem, p_id_local_destino,
    p_inicio, p_fim, IFNULL(p_status, 'planejada')
  );
  SET p_id_viagem = LAST_INSERT_ID();

  SET v_n = JSON_LENGTH(p_trechos_json);
  SET v_i = 0;
  WHILE v_i < v_n DO
    SET v_ordem    = JSON_UNQUOTE(JSON_EXTRACT(p_trechos_json, CONCAT('$[', v_i, '].ordem')));
    SET v_id_modal = JSON_UNQUOTE(JSON_EXTRACT(p_trechos_json, CONCAT('$[', v_i, '].id_modal')));
    SET v_id_linha = JSON_UNQUOTE(JSON_EXTRACT(p_trechos_json, CONCAT('$[', v_i, '].id_linha')));
    SET v_inicio   = JSON_UNQUOTE(JSON_EXTRACT(p_trechos_json, CONCAT('$[', v_i, '].inicio')));
    SET v_fim      = JSON_UNQUOTE(JSON_EXTRACT(p_trechos_json, CONCAT('$[', v_i, '].fim')));
    SET v_dist     = JSON_UNQUOTE(JSON_EXTRACT(p_trechos_json, CONCAT('$[', v_i, '].distancia_km')));

    IF v_id_linha = 'null' OR v_id_linha = '' THEN
      SET v_id_linha = NULL;
    END IF;

    INSERT INTO trecho_viagem (
      id_viagem, ordem, id_modal, id_linha, inicio, fim, distancia_km
    ) VALUES (
      p_id_viagem, v_ordem, v_id_modal, v_id_linha, v_inicio, v_fim, v_dist
    );
    SET v_i = v_i + 1;
  END WHILE;

  COMMIT;
  SET p_mensagem = 'Viagem registrada com sucesso.';
END$$

-- -----------------------------------------------------------------------------
-- Procedure: gerar sugestão sustentável a partir do congestionamento atual
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_gerar_sugestao_sustentavel$$
CREATE PROCEDURE sp_gerar_sugestao_sustentavel(
  IN  p_id_viagem BIGINT UNSIGNED,
  OUT p_id_sugestao BIGINT UNSIGNED,
  OUT p_mensagem VARCHAR(255)
)
proc_sug: BEGIN
  DECLARE v_nivel_medio DECIMAL(5,2);
  DECLARE v_tem_ciclovia TINYINT DEFAULT 0;
  DECLARE v_tem_faixa_onibus TINYINT DEFAULT 0;
  DECLARE v_id_modal SMALLINT UNSIGNED;
  DECLARE v_id_linha INT UNSIGNED;
  DECLARE v_motivo ENUM('congestionamento','menor_co2','menor_tempo');
  DECLARE v_dist DECIMAL(7,3);
  DECLARE v_duracao SMALLINT UNSIGNED;
  DECLARE v_existe INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_id_sugestao = NULL;
    GET DIAGNOSTICS CONDITION 1 p_mensagem = MESSAGE_TEXT;
  END;

  SELECT COUNT(*) INTO v_existe FROM viagem WHERE id_viagem = p_id_viagem;
  IF v_existe = 0 THEN
    SET p_id_sugestao = NULL;
    SET p_mensagem = 'Viagem não encontrada.';
    LEAVE proc_sug;
  END IF;

  -- Congestionamento médio nos segmentos cobertos (ou geral se sem trecho ainda)
  SELECT
    AVG(c.nivel_congestionamento),
    MAX(c.possui_ciclovia),
    MAX(c.faixa_onibus)
  INTO v_nivel_medio, v_tem_ciclovia, v_tem_faixa_onibus
  FROM vw_congestionamento_atual c
  WHERE c.id_segmento IN (
    SELECT ts.id_segmento
    FROM trecho_viagem t
    JOIN trecho_segmento ts ON ts.id_trecho = t.id_trecho
    WHERE t.id_viagem = p_id_viagem
  )
  OR NOT EXISTS (
    SELECT 1
    FROM trecho_viagem t2
    JOIN trecho_segmento ts2 ON ts2.id_trecho = t2.id_trecho
    WHERE t2.id_viagem = p_id_viagem
  );

  IF v_nivel_medio IS NULL THEN
    SELECT AVG(nivel_congestionamento) INTO v_nivel_medio FROM vw_congestionamento_atual;
    SELECT MAX(possui_ciclovia), MAX(faixa_onibus)
      INTO v_tem_ciclovia, v_tem_faixa_onibus
    FROM vw_congestionamento_atual;
  END IF;

  SET v_dist = 5.000; -- estimativa padrão quando ainda sem trechos
  SELECT COALESCE(SUM(distancia_km), 5.000) INTO v_dist
  FROM trecho_viagem WHERE id_viagem = p_id_viagem;

  -- Heurística: congestionamento alto → prioriza metrô/trem; senão bicicleta se ciclovia
  IF IFNULL(v_nivel_medio, 0) >= 3 THEN
    SET v_motivo = 'congestionamento';
    SELECT m.id_modal, (
      SELECT l.id_linha FROM linha_transporte l
      WHERE l.id_modal = m.id_modal ORDER BY l.id_linha LIMIT 1
    )
    INTO v_id_modal, v_id_linha
    FROM modal_transporte m
    WHERE m.codigo = 'METRO' AND m.sustentavel = TRUE
    LIMIT 1;
    SET v_duracao = GREATEST(10, ROUND(v_dist * 3));
  ELSEIF IFNULL(v_tem_ciclovia, 0) = 1 AND v_dist <= 8 THEN
    SET v_motivo = 'menor_co2';
    SELECT id_modal INTO v_id_modal FROM modal_transporte WHERE codigo = 'BICICLETA' LIMIT 1;
    SET v_id_linha = NULL;
    SET v_duracao = GREATEST(10, ROUND(v_dist * 5));
  ELSEIF IFNULL(v_tem_faixa_onibus, 0) = 1 THEN
    SET v_motivo = 'menor_tempo';
    SELECT m.id_modal, (
      SELECT l.id_linha FROM linha_transporte l
      WHERE l.id_modal = m.id_modal ORDER BY l.id_linha LIMIT 1
    )
    INTO v_id_modal, v_id_linha
    FROM modal_transporte m
    WHERE m.codigo = 'ONIBUS' AND m.sustentavel = TRUE
    LIMIT 1;
    SET v_duracao = GREATEST(10, ROUND(v_dist * 4));
  ELSE
    SET v_motivo = 'menor_co2';
    SELECT m.id_modal, (
      SELECT l.id_linha FROM linha_transporte l
      WHERE l.id_modal = m.id_modal ORDER BY l.id_linha LIMIT 1
    )
    INTO v_id_modal, v_id_linha
    FROM modal_transporte m
    WHERE m.codigo = 'METRO' AND m.sustentavel = TRUE
    LIMIT 1;
    SET v_duracao = GREATEST(10, ROUND(v_dist * 3));
  END IF;

  IF v_id_modal IS NULL THEN
    SET p_id_sugestao = NULL;
    SET p_mensagem = 'Nenhum modal sustentável disponível para sugestão.';
    LEAVE proc_sug;
  END IF;

  START TRANSACTION;
  INSERT INTO sugestao_modal (
    id_viagem, id_modal_sugerido, id_linha,
    distancia_estimada_km, duracao_estimada_min, motivo
  ) VALUES (
    p_id_viagem, v_id_modal, v_id_linha,
    v_dist, v_duracao, v_motivo
  );
  SET p_id_sugestao = LAST_INSERT_ID();
  COMMIT;
  SET p_mensagem = CONCAT('Sugestão gerada (motivo=', v_motivo, ').');
END$$

-- -----------------------------------------------------------------------------
-- Procedure: limpeza em lotes de leituras antigas
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_limpar_leituras_antigas$$
CREATE PROCEDURE sp_limpar_leituras_antigas(
  IN p_dias_retencao INT,
  IN p_lote INT
)
BEGIN
  DECLARE v_afetados INT DEFAULT 1;
  DECLARE v_total INT DEFAULT 0;
  IF p_dias_retencao IS NULL OR p_dias_retencao < 1 THEN
    SET p_dias_retencao = 90;
  END IF;
  IF p_lote IS NULL OR p_lote < 1 THEN
    SET p_lote = 5000;
  END IF;

  WHILE v_afetados > 0 DO
    DELETE FROM leitura_trafego
    WHERE registrado_em < (UTC_TIMESTAMP(3) - INTERVAL p_dias_retencao DAY)
    LIMIT p_lote;
    SET v_afetados = ROW_COUNT();
    SET v_total = v_total + v_afetados;
  END WHILE;

  SELECT v_total AS leituras_removidas, p_dias_retencao AS dias_retencao;
END$$

DELIMITER ;

-- EVENT mensal de retenção (habilita o scheduler na sessão/servidor)
SET GLOBAL event_scheduler = ON;

DROP EVENT IF EXISTS ev_limpeza_mensal_leituras;
CREATE EVENT ev_limpeza_mensal_leituras
ON SCHEDULE EVERY 1 MONTH
STARTS TIMESTAMP(DATE_FORMAT(DATE_ADD(UTC_DATE(), INTERVAL 1 MONTH), '%Y-%m-01 03:00:00'))
DO
  CALL sp_limpar_leituras_antigas(90, 5000);

-- ### FIM: 04_procedures.sql ###


-- ##########################################################################
-- INÍCIO: 05_security.sql
-- ##########################################################################

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

-- ### FIM: 05_security.sql ###


-- ##########################################################################
-- INÍCIO: 06_seed.sql
-- ##########################################################################

-- =============================================================================
-- 06_seed.sql – GERADO por scripts/importar_dados_reais.py
-- Rede (GTFS/OSM): scripts/importar_dados_reais.py
-- sensor/leitura: fontes/olhovivo/leitura_trafego_real.sql (Olho Vivo 19/11/2026)
-- Acesso/geração GTFS/OSM (UTC): 2026-11-18; Olho Vivo: 2026-11-19
-- Geometrias: SRID 4326 com axis-order=long-lat
--
-- ORIGEM DOS DADOS (real vs simulado)
-- -----------------------------------------------------------------------------
-- REAL:
--   linha_transporte (+ geom_trajeto), local (paradas/estações): GTFS SPTrans
--     Produtor: https://www.sptrans.com.br/desenvolvedores/ (BaixarGTFS; cadastro). Espelho usado: Mobility Database mdb-8 / GCS mdb-latest.
--     Espelho baixado: GCS mdb-latest (Mobility Database mdb-8)
--     Arquivo local: data/cache/sptrans_gtfs.zip sha256[:16]=45f3cc1ca7d118a2
--     Inclui Metrô e CPTM no mesmo feed (route_type 1 e 2).
--   segmento_via: OpenStreetMap (Nominatim + API 0.6 way/full) — ODbL 1.0
--     https://www.openstreetmap.org/copyright
--     Corredores: Paulista, Rebouças, Consolação, 23 de Maio, Marginal Pinheiros
--   fator_emissao / fonte_referencia: valores REAIS (docs/normalizacao.md)
--     Metrô-SP, MCTI/SIRENE, UK DESNZ
--
-- REAL (também):
--   sensor / leitura_trafego: SPTrans Olho Vivo API v2.1 GET /Posicao
--     https://api.olhovivo.sptrans.com.br/v2.1 | cadastro/token:
--     https://www.sptrans.com.br/desenvolvedores/ (token só em SPTRANS_OLHOVIVO_TOKEN)
--     Janela: 19/11/2026 08:33–09:17 America/Sao_Paulo (UTC−3); 59 leituras;
--     sensores virtuais tipo gps_frota; ids 9 e 10 inativos (Marginal sem cobertura).
--     Caveats: velocidade de ÔNIBUS (inclui paradas); volume = nº de ônibus (não todo o tráfego);
--     nivel_congestionamento DERIVADO (regra do projeto). SQL: fontes/olhovivo/leitura_trafego_real.sql
--     Método: fontes/olhovivo/METODO.md
--
-- SIMULADO (LGPD / domínio interno):
--   usuario / viagem / trecho_viagem / trecho_segmento / sugestao_modal:
--     pessoas fictícias; viagens/sugestões ancoradas em locais/linhas/segmentos reais;
--     distancia_km via haversine entre coordenadas reais.
--   modal_transporte: catálogo interno do produto.
-- =============================================================================

USE mobilidade_urbana;
SET time_zone = '+00:00';
SET NAMES utf8mb4;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE sugestao_modal;
TRUNCATE TABLE trecho_segmento;
TRUNCATE TABLE trecho_viagem;
TRUNCATE TABLE viagem;
TRUNCATE TABLE leitura_trafego;
TRUNCATE TABLE sensor;
TRUNCATE TABLE linha_transporte;
TRUNCATE TABLE segmento_via;
TRUNCATE TABLE local;
TRUNCATE TABLE fator_emissao;
TRUNCATE TABLE fonte_referencia;
TRUNCATE TABLE usuario;
TRUNCATE TABLE modal_transporte;
SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- Modais (catálogo interno) — SIMULADO/catálogo
-- -----------------------------------------------------------------------------
INSERT INTO modal_transporte (id_modal, codigo, nome, categoria, sustentavel, referencia_comparacao) VALUES
(1, 'A_PE', 'A pé', 'ativo', TRUE, FALSE),
(2, 'BICICLETA', 'Bicicleta', 'ativo', TRUE, FALSE),
(3, 'BIKE_ELETRICA', 'Bicicleta/patinete elétrico', 'ativo', TRUE, FALSE),
(4, 'ONIBUS', 'Ônibus municipal', 'coletivo', TRUE, FALSE),
(5, 'METRO', 'Metrô', 'coletivo', TRUE, FALSE),
(6, 'TREM', 'Trem metropolitano (CPTM)', 'coletivo', TRUE, FALSE),
(7, 'CARRO_GASOLINA', 'Carro a gasolina', 'individual', FALSE, TRUE),
(8, 'MOTOCICLETA', 'Motocicleta', 'individual', FALSE, FALSE);

-- -----------------------------------------------------------------------------
-- Fontes e fatores — REAL (docs/normalizacao.md)
-- -----------------------------------------------------------------------------
INSERT INTO fonte_referencia (id_fonte, orgao, titulo, ano_publicacao, url) VALUES
(1, 'Metrô-SP', 'Inventário de Emissões de GEE 2025 (RT-9.EA.25.00/0IV-001)', 2025,
 'https://transparencia.metrosp.com.br/sites/default/files/2025_RT9EA25000IV001_IVEmissoesGEEass.pdf'),
(2, 'Metrô-SP', 'Funcionamento do Metrô evita a emissão de 842 mil toneladas de CO2 em apenas um ano (RMSP: ônibus 80g, carro 120g)', 2020,
 'https://www.metro.sp.gov.br/2020/09/22/funcionamento-do-metro-evita-a-emissao-de-842-mil-toneladas-de-co2-em-apenas-um-ano/'),
(3, 'UK DESNZ', 'Greenhouse gas reporting: conversion factors 2024 – Passenger vehicles – Motorbike Average', 2024,
 'https://www.gov.uk/government/publications/greenhouse-gas-reporting-conversion-factors-2024'),
(4, 'MCTI/SIRENE', 'Fator médio anual do SIN 2025 (Inventários Corporativos) – 0,0461 tCO2/MWh', 2025,
 'https://www.gov.br/mcti/pt-br/acompanhe-o-mcti/sirene/dados-e-ferramentas/fatores-de-emissao');

INSERT INTO fator_emissao (id_modal, id_fonte, g_co2_pkm, estimativa, vigencia_inicio, vigencia_fim) VALUES
(1, NULL, 0.000, TRUE, '2015-01-01', NULL),
(2, NULL, 0.000, TRUE, '2015-01-01', NULL),
(3, 4, 0.700, TRUE, '2025-01-01', NULL),
(4, 2, 80.000, FALSE, '2020-01-01', NULL),
(5, 2, 6.000, FALSE, '2020-01-01', '2025-01-01'),
(5, 1, 3.000, FALSE, '2025-01-01', NULL),
(6, 2, 6.000, TRUE, '2020-01-01', NULL),
(7, 2, 120.000, FALSE, '2020-01-01', NULL),
(8, 3, 113.670, FALSE, '2024-01-01', NULL);

-- -----------------------------------------------------------------------------
-- local — REAL (GTFS stops)
-- -----------------------------------------------------------------------------
INSERT INTO local (id_local, nome, tipo, geom) VALUES
(1, 'Sé', 'estacao', ST_GeomFromText('POINT(-46.633305 -23.550500)', 4326, 'axis-order=long-lat')),
(2, 'Paulista', 'estacao', ST_GeomFromText('POINT(-46.662131 -23.555071)', 4326, 'axis-order=long-lat')),
(3, 'Consolação', 'estacao', ST_GeomFromText('POINT(-46.660205 -23.558094)', 4326, 'axis-order=long-lat')),
(4, 'Pinheiros', 'estacao', ST_GeomFromText('POINT(-46.703082 -23.566631)', 4326, 'axis-order=long-lat')),
(5, 'Luz', 'estacao', ST_GeomFromText('POINT(-46.634300 -23.536600)', 4326, 'axis-order=long-lat')),
(6, 'República', 'estacao', ST_GeomFromText('POINT(-46.642461 -23.544215)', 4326, 'axis-order=long-lat')),
(7, 'Ana Rosa', 'estacao', ST_GeomFromText('POINT(-46.638489 -23.581203)', 4326, 'axis-order=long-lat')),
(8, 'Tucuruvi', 'estacao', ST_GeomFromText('POINT(-46.603209 -23.480049)', 4326, 'axis-order=long-lat')),
(9, 'Jabaquara', 'estacao', ST_GeomFromText('POINT(-46.641028 -23.646033)', 4326, 'axis-order=long-lat')),
(10, 'Vila Madalena', 'estacao', ST_GeomFromText('POINT(-46.691141 -23.546498)', 4326, 'axis-order=long-lat')),
(11, 'Vila Prudente', 'estacao', ST_GeomFromText('POINT(-46.581943 -23.584447)', 4326, 'axis-order=long-lat')),
(12, 'Palmeiras - Barra Funda', 'ponto_onibus', ST_GeomFromText('POINT(-46.666547 -23.525317)', 4326, 'axis-order=long-lat')),
(13, 'Corinthians-itaquera', 'estacao', ST_GeomFromText('POINT(-46.471964 -23.542411)', 4326, 'axis-order=long-lat')),
(14, 'Santo Amaro', 'estacao', ST_GeomFromText('POINT(-46.719702 -23.655909)', 4326, 'axis-order=long-lat')),
(15, 'Capão Redondo', 'estacao', ST_GeomFromText('POINT(-46.768691 -23.659955)', 4326, 'axis-order=long-lat')),
(16, 'Chácara Klabin', 'estacao', ST_GeomFromText('POINT(-46.630999 -23.592990)', 4326, 'axis-order=long-lat')),
(17, 'Paraíso', 'estacao', ST_GeomFromText('POINT(-46.640700 -23.575400)', 4326, 'axis-order=long-lat')),
(18, 'Brigadeiro', 'estacao', ST_GeomFromText('POINT(-46.649027 -23.567615)', 4326, 'axis-order=long-lat')),
(19, 'Trianon-masp', 'estacao', ST_GeomFromText('POINT(-46.653893 -23.563570)', 4326, 'axis-order=long-lat')),
(20, 'Santana', 'estacao', ST_GeomFromText('POINT(-46.624716 -23.502716)', 4326, 'axis-order=long-lat')),
(21, 'Ana Rosa', 'estacao', ST_GeomFromText('POINT(-46.638455 -23.581388)', 4326, 'axis-order=long-lat')),
(22, 'Tiradentes', 'ponto_onibus', ST_GeomFromText('POINT(-46.632672 -23.531324)', 4326, 'axis-order=long-lat')),
(23, 'Santos-imigrantes', 'ponto_onibus', ST_GeomFromText('POINT(-46.620710 -23.595941)', 4326, 'axis-order=long-lat')),
(24, 'Palmeiras - Barra Funda', 'ponto_onibus', ST_GeomFromText('POINT(-46.666803 -23.525703)', 4326, 'axis-order=long-lat')),
(25, 'Pedro II', 'ponto_onibus', ST_GeomFromText('POINT(-46.626281 -23.549742)', 4326, 'axis-order=long-lat')),
(26, 'Penha', 'ponto_onibus', ST_GeomFromText('POINT(-46.542944 -23.533594)', 4326, 'axis-order=long-lat')),
(27, 'Luz', 'estacao', ST_GeomFromText('POINT(-46.634502 -23.536598)', 4326, 'axis-order=long-lat')),
(28, 'Vila Sônia', 'ponto_onibus', ST_GeomFromText('POINT(-46.735692 -23.591689)', 4326, 'axis-order=long-lat')),
(29, 'Pinheiros Metrô', 'estacao', ST_GeomFromText('POINT(-46.701925 -23.567250)', 4326, 'axis-order=long-lat')),
(30, 'Eucaliptos', 'ponto_onibus', ST_GeomFromText('POINT(-46.668649 -23.609840)', 4326, 'axis-order=long-lat')),
(31, 'Largo Treze', 'ponto_onibus', ST_GeomFromText('POINT(-46.710305 -23.654465)', 4326, 'axis-order=long-lat')),
(32, 'Luz', 'estacao', ST_GeomFromText('POINT(-46.635436 -23.535103)', 4326, 'axis-order=long-lat')),
(33, 'Jundiai', 'ponto_onibus', ST_GeomFromText('POINT(-46.871900 -23.195643)', 4326, 'axis-order=long-lat')),
(34, 'Vila Clarice', 'ponto_onibus', ST_GeomFromText('POINT(-46.744207 -23.470038)', 4326, 'axis-order=long-lat')),
(35, 'Baltazar Fidélis', 'ponto_onibus', ST_GeomFromText('POINT(-46.722853 -23.310582)', 4326, 'axis-order=long-lat')),
(36, 'Júlio Prestes', 'ponto_onibus', ST_GeomFromText('POINT(-46.640763 -23.532964)', 4326, 'axis-order=long-lat')),
(37, 'Amador Bueno', 'ponto_onibus', ST_GeomFromText('POINT(-46.983928 -23.530700)', 4326, 'axis-order=long-lat')),
(38, 'Comandante Sampaio', 'ponto_onibus', ST_GeomFromText('POINT(-46.796059 -23.525990)', 4326, 'axis-order=long-lat')),
(39, 'Jardim Belval', 'ponto_onibus', ST_GeomFromText('POINT(-46.889290 -23.514306)', 4326, 'axis-order=long-lat')),
(40, 'Osasco', 'ponto_onibus', ST_GeomFromText('POINT(-46.776007 -23.527834)', 4326, 'axis-order=long-lat')),
(41, 'Varginha', 'ponto_onibus', ST_GeomFromText('POINT(-46.712051 -23.770367)', 4326, 'axis-order=long-lat')),
(42, 'Cidade Jardim', 'ponto_onibus', ST_GeomFromText('POINT(-46.691293 -23.585337)', 4326, 'axis-order=long-lat')),
(43, 'Socorro', 'ponto_onibus', ST_GeomFromText('POINT(-46.710970 -23.663430)', 4326, 'axis-order=long-lat')),
(44, 'R. Durval Fontoura Castro, 19', 'ponto_onibus', ST_GeomFromText('POINT(-46.662848 -23.643399)', 4326, 'axis-order=long-lat')),
(45, 'R. Vanderlei, 1602', 'ponto_onibus', ST_GeomFromText('POINT(-46.681145 -23.535985)', 4326, 'axis-order=long-lat')),
(46, 'Parada 2 - Metrô São Judas B/C', 'estacao', ST_GeomFromText('POINT(-46.640544 -23.625210)', 4326, 'axis-order=long-lat')),
(47, 'Parada 2 - Frei Caneca', 'ponto_onibus', ST_GeomFromText('POINT(-46.659175 -23.558768)', 4326, 'axis-order=long-lat')),
(48, 'Terminal Metrô Butantã', 'ponto_onibus', ST_GeomFromText('POINT(-46.708304 -23.571884)', 4326, 'axis-order=long-lat')),
(49, 'Terminal Parque Dom Pedro II - Plat 01', 'ponto_onibus', ST_GeomFromText('POINT(-46.630612 -23.546826)', 4326, 'axis-order=long-lat')),
(50, 'Oscar Freire B/C', 'ponto_onibus', ST_GeomFromText('POINT(-46.672095 -23.560639)', 4326, 'axis-order=long-lat')),
(51, 'Parada 2 - Viaduto Do Chá', 'ponto_onibus', ST_GeomFromText('POINT(-46.639045 -23.546473)', 4326, 'axis-order=long-lat')),
(52, 'R. Prof. Wilfrides Alves De Lima', 'ponto_onibus', ST_GeomFromText('POINT(-46.666781 -23.527350)', 4326, 'axis-order=long-lat')),
(53, 'R. Gilberto Sabino, 169', 'ponto_onibus', ST_GeomFromText('POINT(-46.701158 -23.566935)', 4326, 'axis-order=long-lat')),
(54, 'Av. Sumaré, 740', 'ponto_onibus', ST_GeomFromText('POINT(-46.674274 -23.535436)', 4326, 'axis-order=long-lat')),
(55, 'Viad. Paulo Vi', 'ponto_onibus', ST_GeomFromText('POINT(-46.681983 -23.555564)', 4326, 'axis-order=long-lat')),
(56, 'Terminal Pirituba', 'ponto_onibus', ST_GeomFromText('POINT(-46.725770 -23.485997)', 4326, 'axis-order=long-lat')),
(57, 'R. Vergueiro, 2776', 'ponto_onibus', ST_GeomFromText('POINT(-46.635893 -23.585768)', 4326, 'axis-order=long-lat')),
(58, 'Av. Dos Remédios, 631', 'ponto_onibus', ST_GeomFromText('POINT(-46.753202 -23.518666)', 4326, 'axis-order=long-lat')),
(59, 'R. Cerro Cora, 613', 'ponto_onibus', ST_GeomFromText('POINT(-46.703086 -23.540495)', 4326, 'axis-order=long-lat')),
(60, 'R. Francisco Ricarte Da Silva', 'ponto_onibus', ST_GeomFromText('POINT(-46.756116 -23.662318)', 4326, 'axis-order=long-lat'));

-- -----------------------------------------------------------------------------
-- segmento_via — REAL (OpenStreetMap ODbL)
-- -----------------------------------------------------------------------------
INSERT INTO segmento_via (id_segmento, nome_via, geom, velocidade_max_kmh, possui_ciclovia, faixa_onibus) VALUES
(1, 'Avenida Paulista [OSM way 261785599]', ST_GeomFromText('LINESTRING(-46.648746 -23.567945, -46.648519 -23.568120, -46.648244 -23.568330, -46.647752 -23.568709, -46.647511 -23.568889, -46.647413 -23.568964, -46.647051 -23.569241, -46.646784 -23.569445, -46.646533 -23.569637)', 4326, 'axis-order=long-lat'), 50, FALSE, TRUE),
(2, 'Avenida Paulista [OSM way 231341013]', ST_GeomFromText('LINESTRING(-46.649215 -23.567405, -46.650481 -23.566352, -46.650529 -23.566312, -46.650697 -23.566163, -46.650784 -23.566091)', 4326, 'axis-order=long-lat'), 50, FALSE, TRUE),
(3, 'Avenida Rebouças [OSM way 329094557]', ST_GeomFromText('LINESTRING(-46.684526 -23.567875, -46.684419 -23.567818, -46.683987 -23.567587, -46.683576 -23.567368, -46.682094 -23.566584, -46.681899 -23.566479, -46.680514 -23.565745, -46.680452 -23.565712)', 4326, 'axis-order=long-lat'), 50, TRUE, TRUE),
(4, 'Avenida Rebouças [OSM way 426510608]', ST_GeomFromText('LINESTRING(-46.671862 -23.560531, -46.671428 -23.560300, -46.671126 -23.560130, -46.670431 -23.559737, -46.670083 -23.559539, -46.669574 -23.559259, -46.669146 -23.559000)', 4326, 'axis-order=long-lat'), 50, TRUE, TRUE),
(5, 'Rua da Consolação [OSM way 405489974]', ST_GeomFromText('LINESTRING(-46.660998 -23.553993, -46.661056 -23.554041, -46.661301 -23.554243, -46.661720 -23.554587, -46.661985 -23.554806, -46.662194 -23.554977, -46.662297 -23.555061, -46.662349 -23.555104, -46.662396 -23.555143, -46.662658 -23.555359, -46.662773 -23.555453, -46.662791 -23.555468, -46.662899 -23.555556)', 4326, 'axis-order=long-lat'), 50, TRUE, TRUE),
(6, 'Rua da Consolação [OSM way 935573768]', ST_GeomFromText('LINESTRING(-46.654769 -23.550297, -46.655293 -23.550598, -46.656467 -23.551203, -46.656612 -23.551279)', 4326, 'axis-order=long-lat'), 50, TRUE, TRUE),
(7, 'Avenida Vinte e Três de Maio [OSM way 241249687]', ST_GeomFromText('LINESTRING(-46.640716 -23.570443, -46.640687 -23.570078, -46.640573 -23.568505, -46.640522 -23.567969, -46.640499 -23.567574, -46.640510 -23.567112, -46.640554 -23.566355, -46.640573 -23.565971)', 4326, 'axis-order=long-lat'), 60, FALSE, FALSE),
(8, 'Avenida Vinte e Três de Maio [OSM way 286269721]', ST_GeomFromText('LINESTRING(-46.653030 -23.586968, -46.652224 -23.588639, -46.651543 -23.590075, -46.651417 -23.590339)', 4326, 'axis-order=long-lat'), 60, FALSE, FALSE),
(9, 'Marginal Pinheiros (Expressa) [OSM way 768961582]', ST_GeomFromText('LINESTRING(-46.690759 -23.586509, -46.690777 -23.586121, -46.690814 -23.585772, -46.690873 -23.585441, -46.690948 -23.585172, -46.691035 -23.584931, -46.691204 -23.584523, -46.691401 -23.584122, -46.691769 -23.583443, -46.692360 -23.582416, -46.692937 -23.581445, -46.693414 -23.580617, -46.694232 -23.579170, -46.694724 -23.578296, -46.695137 -23.577574, -46.695930 -23.576237, -46.696250 -23.575764, -46.696490 -23.575447, -46.696655 -23.575253, -46.696870 -23.575038, -46.697115 -23.574798)', 4326, 'axis-order=long-lat'), 90, FALSE, FALSE),
(10, 'Marginal Pinheiros (Expressa) [OSM way 96085719]', ST_GeomFromText('LINESTRING(-46.698504 -23.575482, -46.697983 -23.575968, -46.697771 -23.576191, -46.697622 -23.576392, -46.697323 -23.576815, -46.696822 -23.577639, -46.694815 -23.581099, -46.694748 -23.581220, -46.693776 -23.582913, -46.693174 -23.583883)', 4326, 'axis-order=long-lat'), 90, TRUE, FALSE);

INSERT INTO sensor (id_sensor, id_segmento, tipo, geom, instalado_em, status) VALUES
(1, 1, 'gps_frota', ST_GeomFromText('POINT(-46.647511 -23.568889)', 4326, 'axis-order=long-lat'), '2026-11-19', 'ativo'),
(2, 2, 'gps_frota', ST_GeomFromText('POINT(-46.650529 -23.566312)', 4326, 'axis-order=long-lat'), '2026-11-19', 'ativo'),
(3, 3, 'gps_frota', ST_GeomFromText('POINT(-46.682094 -23.566584)', 4326, 'axis-order=long-lat'), '2026-11-19', 'ativo'),
(4, 4, 'gps_frota', ST_GeomFromText('POINT(-46.670431 -23.559737)', 4326, 'axis-order=long-lat'), '2026-11-19', 'ativo'),
(5, 5, 'gps_frota', ST_GeomFromText('POINT(-46.662297 -23.555061)', 4326, 'axis-order=long-lat'), '2026-11-19', 'ativo'),
(6, 6, 'gps_frota', ST_GeomFromText('POINT(-46.656467 -23.551203)', 4326, 'axis-order=long-lat'), '2026-11-19', 'ativo'),
(7, 7, 'gps_frota', ST_GeomFromText('POINT(-46.640499 -23.567574)', 4326, 'axis-order=long-lat'), '2026-11-19', 'ativo'),
(8, 8, 'gps_frota', ST_GeomFromText('POINT(-46.651543 -23.590075)', 4326, 'axis-order=long-lat'), '2026-11-19', 'ativo'),
(9, 9, 'gps_frota', ST_GeomFromText('POINT(-46.692937 -23.581445)', 4326, 'axis-order=long-lat'), '2026-11-19', 'inativo'),
(10, 10, 'gps_frota', ST_GeomFromText('POINT(-46.696822 -23.577639)', 4326, 'axis-order=long-lat'), '2026-11-19', 'inativo');

-- -----------------------------------------------------------------------------
-- leitura_trafego — REAL (derivado de GET /Posicao, SPTrans Olho Vivo v2.1)
-- comentário de cada linha: hora local SP | pares usados | linhas de ônibus
-- -----------------------------------------------------------------------------
-- sensor 9 (Marginal Pinheiros (Expressa) [OSM way 768961582]): 23 posição(ões) no buffer, 1 par(es) válido(s) de 1 ônibus -> nenhuma janela com ≥ 2 ônibus; SEM leituras, sensor 'inativo'
-- sensor 10 (Marginal Pinheiros (Expressa) [OSM way 96085719]): 0 posição(ões) no buffer, 0 par(es) válido(s) de 0 ônibus -> nenhuma janela com ≥ 2 ônibus; SEM leituras, sensor 'inativo'
INSERT INTO leitura_trafego (id_sensor, registrado_em, velocidade_media_kmh, volume_veiculos, nivel_congestionamento) VALUES
(1, '2026-11-19 11:30:00.000', 1.8, 4, 5),  -- 19/11/2026 08:30 SP | 6 par(es) | 5154-10, 715M-10, 805L-10, 857R-10
(1, '2026-11-19 11:35:00.000', 4.4, 9, 5),  -- 19/11/2026 08:35 SP | 14 par(es) | 5175-10, 715M-10, 775P-10, 857P-10, 857R-10, 975A-10
(1, '2026-11-19 11:40:00.000', 7.9, 10, 4),  -- 19/11/2026 08:40 SP | 15 par(es) | 5119-10, 715M-10, 857P-10, 857R-10, 875H-10, 875P-10, 877T-10, 917H-10, 975A-10
(1, '2026-11-19 11:50:00.000', 7.1, 7, 4),  -- 19/11/2026 08:50 SP | 9 par(es) | 175P-10, 478P-10, 508L-10, 5185-10, 715M-10, 857P-10, 874T-10
(1, '2026-11-19 11:55:00.000', 9.3, 6, 4),  -- 19/11/2026 08:55 SP | 7 par(es) | 175P-10, 475R-10, 477A-10, 857R-10, 874T-10, 875H-10
(1, '2026-11-19 12:05:00.000', 12.5, 7, 3),  -- 19/11/2026 09:05 SP | 8 par(es) | 175P-10, 478P-10, 857R-10, 877T-10, 917H-10, 917M-10
(1, '2026-11-19 12:10:00.000', 7.9, 12, 4),  -- 19/11/2026 09:10 SP | 23 par(es) | 477A-10, 5119-10, 7550-10, 857R-10, 874T-10, 875P-10, 917H-10, 917M-10, 975A-10
(1, '2026-11-19 12:15:00.000', 4.4, 4, 5),  -- 19/11/2026 09:15 SP | 5 par(es) | 5154-10, 857P-10, 874T-10, 875H-10
(2, '2026-11-19 11:30:00.000', 5.0, 2, 5),  -- 19/11/2026 08:30 SP | 2 par(es) | 478P-10, 5154-10
(2, '2026-11-19 11:35:00.000', 6.6, 11, 4),  -- 19/11/2026 08:35 SP | 15 par(es) | 478P-10, 5175-10, 7550-10, 775P-10, 805L-10, 857P-10, 857R-10, 875H-10, 875P-10, 975A-10
(2, '2026-11-19 11:40:00.000', 11.8, 12, 4),  -- 19/11/2026 08:40 SP | 21 par(es) | 5119-10, 669A-10, 715M-10, 857P-10, 875A-10, 875H-10, 875P-10, 877T-10, 975A-10
(2, '2026-11-19 11:50:00.000', 3.0, 4, 5),  -- 19/11/2026 08:50 SP | 6 par(es) | 478P-10, 5185-10, 715M-10, 875A-10
(2, '2026-11-19 11:55:00.000', 8.5, 8, 4),  -- 19/11/2026 08:55 SP | 14 par(es) | 175P-10, 475R-10, 715M-10, 857P-10, 857R-10, 874T-10, 917M-31
(2, '2026-11-19 12:05:00.000', 7.0, 10, 4),  -- 19/11/2026 09:05 SP | 14 par(es) | 175P-10, 715M-10, 857R-10, 875H-10, 875P-10, 877T-10, 917M-10, 975A-10
(2, '2026-11-19 12:10:00.000', 6.9, 9, 4),  -- 19/11/2026 09:10 SP | 14 par(es) | 477A-10, 478P-10, 5119-10, 7550-10, 857R-10, 875H-10, 917M-10
(3, '2026-11-19 11:30:00.000', 17.2, 4, 3),  -- 19/11/2026 08:30 SP | 6 par(es) | 702C-10, 7545-10, 7545-21
(3, '2026-11-19 11:35:00.000', 15.3, 13, 3),  -- 19/11/2026 08:35 SP | 25 par(es) | 702C-10, 702U-10, 715M-10, 7245-10, 7411-10, 7545-10, 857P-10, 857R-10, 8700-1, 8705-10, 8707-10
(3, '2026-11-19 11:40:00.000', 12.2, 15, 4),  -- 19/11/2026 08:40 SP | 29 par(es) | 702C-10, 715M-10, 7245-10, 7545-10, 7903-10, 857R-10, 8700-1, 8700-10, 8705-10, 8707-10
(3, '2026-11-19 11:50:00.000', 13.2, 11, 3),  -- 19/11/2026 08:50 SP | 22 par(es) | 702U-10, 715M-10, 7545-10, 775P-10, 857R-10, 8700-1, 8700-10, 8707-10
(3, '2026-11-19 11:55:00.000', 13.5, 12, 3),  -- 19/11/2026 08:55 SP | 22 par(es) | 702U-10, 715M-10, 7245-10, 7545-10, 775P-10, 778R-10, 809V-10, 857P-10, 8700-1, 8700-10, 8705-10, 8707-10
(3, '2026-11-19 12:05:00.000', 21.5, 14, 2),  -- 19/11/2026 09:05 SP | 22 par(es) | 702U-10, 715M-10, 7411-10, 778R-10, 7903-10, 809V-10, 857P-10, 857R-10, 8700-1, 8700-10, 8707-10
(3, '2026-11-19 12:10:00.000', 18.5, 14, 3),  -- 19/11/2026 09:10 SP | 18 par(es) | 702C-10, 715M-10, 7545-10, 778R-10, 857P-10, 857R-10, 8700-1, 8705-10, 8707-10
(3, '2026-11-19 12:15:00.000', 36.5, 3, 0),  -- 19/11/2026 09:15 SP | 3 par(es) | 8700-10, 8705-10
(4, '2026-11-19 11:35:00.000', 19.8, 9, 3),  -- 19/11/2026 08:35 SP | 9 par(es) | 702C-10, 7545-21, 778R-10, 7903-10, 809V-10, 8700-1, 8700-10, 8707-10
(4, '2026-11-19 11:40:00.000', 17.4, 3, 3),  -- 19/11/2026 08:40 SP | 3 par(es) | 702U-10, 715M-10, 857P-10
(4, '2026-11-19 11:50:00.000', 15.4, 4, 3),  -- 19/11/2026 08:50 SP | 4 par(es) | 715M-10, 857R-10, 8700-1, 8700-10
(4, '2026-11-19 11:55:00.000', 17.3, 2, 3),  -- 19/11/2026 08:55 SP | 2 par(es) | 7545-10, 8700-10
(4, '2026-11-19 12:05:00.000', 11.4, 10, 4),  -- 19/11/2026 09:05 SP | 13 par(es) | 715M-10, 7545-10, 7545-21, 778R-10, 857P-10, 857R-10, 8700-1, 8700-10, 8705-10
(4, '2026-11-19 12:10:00.000', 11.0, 10, 4),  -- 19/11/2026 09:10 SP | 15 par(es) | 702U-10, 715M-10, 7411-10, 7545-10, 778R-10, 857P-10, 8700-1, 8700-10, 8705-10
(4, '2026-11-19 12:15:00.000', 22.8, 4, 2),  -- 19/11/2026 09:15 SP | 4 par(es) | 715M-10, 778R-10, 8707-10
(5, '2026-11-19 11:30:00.000', 4.2, 6, 5),  -- 19/11/2026 08:30 SP | 8 par(es) | 508L-10, 701A-10, 7903-10, 8700-1, 875A-10, 917H-10
(5, '2026-11-19 11:35:00.000', 7.8, 9, 4),  -- 19/11/2026 08:35 SP | 14 par(es) | 669A-10, 702C-10, 7281-10, 7545-10, 8700-1, 8700-10, 8707-10, 909T-10
(5, '2026-11-19 11:40:00.000', 8.2, 10, 4),  -- 19/11/2026 08:40 SP | 17 par(es) | 178L-10, 701U-10, 702U-10, 7267-10, 7282-10, 7545-10, 809V-10, 8700-10, 8705-10
(5, '2026-11-19 11:50:00.000', 9.3, 9, 4),  -- 19/11/2026 08:50 SP | 12 par(es) | 702U-10, 7267-10, 7545-10, 778R-10, 8700-10, 877T-10, 917M-31
(5, '2026-11-19 11:55:00.000', 13.3, 3, 3),  -- 19/11/2026 08:55 SP | 3 par(es) | 175P-10, 701A-10, 877T-10
(5, '2026-11-19 12:05:00.000', 6.7, 13, 4),  -- 19/11/2026 09:05 SP | 27 par(es) | 178L-10, 701A-10, 701U-10, 702C-10, 7267-10, 7272-10, 7281-10, 7545-10, 8700-1, 8700-10, 8705-10, 909T-1
(5, '2026-11-19 12:10:00.000', 6.7, 11, 4),  -- 19/11/2026 09:10 SP | 18 par(es) | 178L-10, 508L-10, 669A-10, 701U-10, 702U-10, 7281-10, 7282-10, 7545-10, 8707-10, 874T-10, 877T-10
(5, '2026-11-19 12:15:00.000', 7.0, 5, 4),  -- 19/11/2026 09:15 SP | 6 par(es) | 178L-10, 701U-10, 7272-10, 8700-1, 909T-10
(6, '2026-11-19 11:35:00.000', 18.9, 6, 3),  -- 19/11/2026 08:35 SP | 6 par(es) | 178L-10, 702U-10, 7411-10, 7545-10, 8700-1, 8700-10
(6, '2026-11-19 11:40:00.000', 17.3, 13, 3),  -- 19/11/2026 08:40 SP | 13 par(es) | 669A-10, 702C-10, 702U-10, 7267-10, 7272-10, 7281-10, 7282-10, 7545-10, 7903-10, 8700-1, 909T-10
(6, '2026-11-19 11:55:00.000', 17.3, 2, 3),  -- 19/11/2026 08:55 SP | 2 par(es) | 178L-10, 669A-10
(6, '2026-11-19 12:05:00.000', 17.4, 12, 3),  -- 19/11/2026 09:05 SP | 12 par(es) | 669A-10, 702U-10, 7281-10, 7282-10, 7545-10, 8700-1, 8700-10, 8705-10, 874T-10, 877T-10
(6, '2026-11-19 12:10:00.000', 20.4, 6, 2),  -- 19/11/2026 09:10 SP | 6 par(es) | 178L-10, 508L-10, 701U-10, 8700-10, 8705-10, 874T-10
(6, '2026-11-19 12:15:00.000', 19.4, 5, 3),  -- 19/11/2026 09:15 SP | 5 par(es) | 669A-10, 7267-10, 7411-10, 7903-10, 874T-10
(7, '2026-11-19 11:35:00.000', 28.4, 5, 2),  -- 19/11/2026 08:35 SP | 5 par(es) | 5362-10, 5391-10, 5630-10, 6455-10
(7, '2026-11-19 11:40:00.000', 18.2, 3, 3),  -- 19/11/2026 08:40 SP | 3 par(es) | 509M-10, 5318-10, 5630-10
(7, '2026-11-19 11:50:00.000', 25.4, 4, 2),  -- 19/11/2026 08:50 SP | 5 par(es) | 175T-10, 5318-10, 5391-10, 5652-10
(7, '2026-11-19 11:55:00.000', 28.3, 5, 2),  -- 19/11/2026 08:55 SP | 5 par(es) | 175T-10, 509M-10, 5362-10, 5614-10, 5630-10
(7, '2026-11-19 12:05:00.000', 27.6, 5, 2),  -- 19/11/2026 09:05 SP | 5 par(es) | 175T-10, 5300-10, 5391-10, 5391-21, 5630-21
(7, '2026-11-19 12:10:00.000', 28.5, 7, 2),  -- 19/11/2026 09:10 SP | 8 par(es) | 175T-10, 5362-10, 5391-10, 5614-10, 5652-10, 5705-10
(7, '2026-11-19 12:15:00.000', 25.1, 5, 2),  -- 19/11/2026 09:15 SP | 5 par(es) | 5370-10, 5630-10, 5652-10, 6455-10
(8, '2026-11-19 11:30:00.000', 13.3, 2, 4),  -- 19/11/2026 08:30 SP | 2 par(es) | 509M-10, 5175-10
(8, '2026-11-19 11:35:00.000', 13.3, 10, 4),  -- 19/11/2026 08:35 SP | 12 par(es) | 509J-10, 5164-10, 5175-10, 5300-10, 5362-22, 5391-21, 5611-10, 5630-10, 6358-10
(8, '2026-11-19 11:40:00.000', 17.8, 8, 3),  -- 19/11/2026 08:40 SP | 10 par(es) | 5175-10, 5178-10, 5317-10, 5370-21, 5391-10, 5614-10, 6358-10, 857A-10
(8, '2026-11-19 11:50:00.000', 15.1, 8, 3),  -- 19/11/2026 08:50 SP | 8 par(es) | 175T-10, 5164-21, 5175-10, 5178-10, 5611-10, 6358-10, 675N-10
(8, '2026-11-19 11:55:00.000', 19.0, 8, 3),  -- 19/11/2026 08:55 SP | 9 par(es) | 509M-10, 5164-21, 5185-10, 5300-10, 5391-10, 857A-10
(8, '2026-11-19 12:05:00.000', 16.4, 10, 3),  -- 19/11/2026 09:05 SP | 12 par(es) | 175T-10, 509M-10, 5154-10, 5175-10, 5178-10, 5194-10, 5370-10, 6455-10, 857A-10
(8, '2026-11-19 12:10:00.000', 15.9, 10, 3),  -- 19/11/2026 09:10 SP | 12 par(es) | 175T-10, 509M-10, 5175-10, 5178-10, 5185-10, 5362-10, 5611-10, 6358-10, 709A-10
(8, '2026-11-19 12:15:00.000', 17.0, 2, 3);  -- 19/11/2026 09:15 SP | 2 par(es) | 5175-10, 5300-10

-- -----------------------------------------------------------------------------
-- linha_transporte — REAL (GTFS shapes; SPTrans + Metrô + CPTM)
-- -----------------------------------------------------------------------------
INSERT INTO linha_transporte (id_linha, id_modal, codigo, nome, operadora, geom_trajeto) VALUES
(1, 5, 'L1', 'METRÔ L1 — TUCURUVI - JABAQUARA', 'Metrô-SP', ST_GeomFromText('LINESTRING(-46.641050 -23.646351, -46.641274 -23.644041, -46.641444 -23.641629, -46.641324 -23.639471, -46.641243 -23.636810, -46.641280 -23.634974, -46.641551 -23.633344, -46.641557 -23.632522, -46.641493 -23.631113, -46.641287 -23.628316, -46.641192 -23.627028, -46.640731 -23.625355, -46.640262 -23.623313, -46.639515 -23.619940, -46.638997 -23.617618, -46.638212 -23.614015, -46.637883 -23.611877, -46.637923 -23.610411, -46.637846 -23.608298, -46.637388 -23.606362, -46.636759 -23.604266, -46.636697 -23.601730, -46.636676 -23.598996, -46.636636 -23.597418, -46.636645 -23.595560, -46.636591 -23.592963, -46.636106 -23.591769, -46.635315 -23.590786, -46.634780 -23.589589, -46.634578 -23.588352, -46.634770 -23.587414, -46.635491 -23.586076, -46.636518 -23.584452, -46.637530 -23.582827, -46.637915 -23.582238, -46.638472 -23.581355, -46.638578 -23.581195, -46.639429 -23.579856, -46.639904 -23.579092, -46.640568 -23.578041, -46.640873 -23.577049, -46.640821 -23.576087, -46.640664 -23.574657, -46.640009 -23.571899, -46.639911 -23.570818, -46.639897 -23.568527, -46.639635 -23.566222, -46.638680 -23.561899, -46.638379 -23.560693, -46.637026 -23.558210, -46.636113 -23.556293, -46.634878 -23.553915, -46.633660 -23.551395, -46.633402 -23.549117, -46.633814 -23.544997, -46.634449 -23.541122, -46.634561 -23.537945, -46.635349 -23.535167, -46.633080 -23.532593, -46.631321 -23.528142, -46.630136 -23.526175, -46.628086 -23.524795, -46.626863 -23.524259, -46.625618 -23.523050, -46.625327 -23.520935, -46.625152 -23.516435, -46.625055 -23.512961, -46.624947 -23.509254, -46.624848 -23.505576, -46.624659 -23.500279, -46.624153 -23.498143, -46.618357 -23.493424, -46.616397 -23.492118, -46.613026 -23.489839, -46.611283 -23.489581, -46.609884 -23.488794, -46.608289 -23.485925, -46.606576 -23.483181, -46.604400 -23.481103, -46.603209 -23.480049)', 4326, 'axis-order=long-lat')),
(2, 5, 'L2', 'METRÔ L2 — VILA MADALENA - VILA PRUDENTE', 'Metrô-SP', ST_GeomFromText('LINESTRING(-46.691141 -23.546498, -46.690267 -23.546939, -46.689025 -23.547508, -46.687563 -23.547571, -46.686853 -23.547695, -46.685603 -23.548276, -46.684589 -23.549168, -46.684110 -23.549514, -46.681762 -23.549660, -46.680858 -23.549771, -46.679446 -23.550002, -46.677573 -23.550976, -46.676527 -23.551686, -46.673754 -23.552915, -46.669976 -23.554480, -46.668348 -23.555104, -46.666940 -23.555176, -46.665927 -23.554687, -46.664880 -23.554386, -46.663840 -23.555001, -46.662996 -23.555663, -46.661866 -23.556665, -46.660224 -23.558087, -46.655382 -23.562334, -46.653789 -23.563664, -46.652868 -23.564420, -46.649453 -23.567239, -46.648918 -23.567689, -46.643125 -23.572178, -46.641323 -23.573764, -46.641042 -23.574274, -46.640805 -23.575377, -46.640790 -23.576351, -46.640841 -23.576833, -46.640600 -23.577895, -46.639731 -23.579290, -46.639129 -23.580239, -46.638586 -23.581021, -46.638419 -23.581289, -46.638131 -23.581764, -46.637850 -23.582228, -46.637470 -23.582818, -46.636958 -23.583620, -46.636328 -23.584616, -46.635524 -23.585878, -46.635151 -23.586473, -46.634965 -23.586825, -46.634711 -23.587413, -46.634516 -23.588327, -46.634368 -23.589152, -46.634180 -23.589562, -46.633147 -23.590448, -46.631791 -23.591471, -46.630283 -23.592947, -46.629180 -23.594004, -46.628610 -23.594583, -46.626264 -23.595292, -46.624082 -23.595448, -46.622590 -23.595231, -46.620813 -23.595863, -46.619847 -23.596310, -46.617860 -23.597589, -46.616649 -23.598796, -46.615796 -23.599461, -46.614833 -23.600886, -46.612598 -23.602214, -46.608864 -23.602387, -46.605579 -23.601981, -46.603732 -23.601510, -46.600335 -23.600889, -46.597954 -23.600238, -46.596933 -23.599357, -46.594816 -23.597672, -46.592195 -23.595662, -46.591009 -23.594344, -46.587597 -23.591240, -46.583792 -23.587917, -46.583131 -23.585087, -46.583015 -23.584824, -46.581932 -23.584429)', 4326, 'axis-order=long-lat')),
(3, 5, 'L3', 'METRÔ L3 — CORINTHIANS - ITAQUERA - PALMEIRAS - BARRA FUNDA', 'Metrô-SP', ST_GeomFromText('LINESTRING(-46.666964 -23.525590, -46.665252 -23.526207, -46.661450 -23.528138, -46.660715 -23.529370, -46.658638 -23.532119, -46.655833 -23.533810, -46.652968 -23.535595, -46.650272 -23.537269, -46.648971 -23.538128, -46.647954 -23.539006, -46.646964 -23.540078, -46.645732 -23.541238, -46.644140 -23.542734, -46.642686 -23.544076, -46.642359 -23.544459, -46.641714 -23.545346, -46.640890 -23.546449, -46.639232 -23.547788, -46.638326 -23.548217, -46.636310 -23.549136, -46.632397 -23.550796, -46.631039 -23.550936, -46.629900 -23.550732, -46.628458 -23.550202, -46.625921 -23.549690, -46.622090 -23.549033, -46.618919 -23.548308, -46.615917 -23.547863, -46.615407 -23.547799, -46.613212 -23.547620, -46.609989 -23.546972, -46.606672 -23.546288, -46.598401 -23.544625, -46.594179 -23.543743, -46.590237 -23.543029, -46.585029 -23.542002, -46.580054 -23.541164, -46.576821 -23.540520, -46.574577 -23.540051, -46.572156 -23.539298, -46.569727 -23.538884, -46.567147 -23.538398, -46.563190 -23.537611, -46.557113 -23.536391, -46.549679 -23.534871, -46.544066 -23.533803, -46.541399 -23.533275, -46.540323 -23.533069, -46.534785 -23.531977, -46.532369 -23.531719, -46.530897 -23.531895, -46.528991 -23.532093, -46.527142 -23.531950, -46.522881 -23.531548, -46.520624 -23.531146, -46.518715 -23.530340, -46.516774 -23.529371, -46.515603 -23.528832, -46.513775 -23.528141, -46.510460 -23.527626, -46.508145 -23.527512, -46.506331 -23.527997, -46.505052 -23.528787, -46.503041 -23.530169, -46.499357 -23.532514, -46.496389 -23.534636, -46.495116 -23.535233, -46.493501 -23.535512, -46.490469 -23.535759, -46.487984 -23.535963, -46.486662 -23.537163, -46.485916 -23.538761, -46.484775 -23.540174, -46.484276 -23.540645, -46.483329 -23.541345, -46.482033 -23.541858, -46.479555 -23.542441, -46.477530 -23.542881, -46.473181 -23.542638, -46.471267 -23.541986)', 4326, 'axis-order=long-lat')),
(4, 5, 'L4', 'METRÔ L4 — SÃO PAULO - MORUMBI - LUZ', 'ViaQuatro / Metrô-SP', ST_GeomFromText('LINESTRING(-46.635349 -23.535167, -46.635158 -23.537704, -46.636127 -23.538976, -46.637079 -23.539720, -46.638218 -23.540498, -46.639608 -23.541483, -46.640676 -23.542390, -46.642524 -23.543973, -46.642602 -23.544031, -46.643801 -23.545030, -46.645642 -23.546464, -46.646473 -23.546852, -46.646803 -23.546964, -46.647724 -23.547500, -46.649675 -23.548133, -46.651016 -23.548531, -46.652015 -23.548889, -46.653290 -23.549572, -46.656367 -23.551223, -46.657506 -23.551867, -46.658442 -23.552346, -46.659552 -23.553079, -46.660836 -23.554000, -46.662098 -23.555046, -46.662912 -23.555658, -46.665274 -23.556641, -46.666671 -23.557365, -46.666953 -23.557537, -46.667022 -23.557584, -46.671741 -23.560373, -46.672061 -23.560555, -46.674819 -23.562234, -46.675585 -23.562805, -46.676657 -23.563596, -46.677605 -23.564109, -46.677979 -23.564207, -46.678401 -23.564214, -46.679397 -23.564188, -46.682422 -23.565345, -46.685700 -23.566691, -46.688855 -23.567820, -46.689961 -23.567896, -46.691865 -23.567719, -46.694134 -23.567237, -46.694345 -23.567203, -46.695507 -23.567047, -46.696504 -23.567015, -46.697843 -23.567037, -46.698892 -23.567062, -46.699793 -23.567083, -46.701627 -23.567195, -46.702306 -23.567311, -46.703005 -23.567449, -46.703738 -23.567614, -46.704801 -23.568054, -46.705685 -23.568821, -46.706896 -23.570104, -46.707369 -23.570765, -46.707954 -23.571643, -46.708942 -23.573812, -46.709531 -23.575679, -46.710401 -23.579066, -46.711345 -23.580386, -46.712482 -23.581868, -46.715439 -23.583323, -46.717044 -23.583943, -46.717671 -23.584365, -46.718266 -23.584625, -46.718937 -23.584725, -46.720031 -23.584916, -46.723543 -23.586170, -46.725689 -23.586966, -46.726637 -23.587543, -46.729325 -23.589137, -46.730879 -23.590575, -46.732186 -23.591903, -46.733156 -23.592347, -46.734522 -23.592625, -46.735244 -23.592297, -46.735706 -23.591650)', 4326, 'axis-order=long-lat')),
(5, 5, 'L5', 'METRÔ L5 — CAPAO REDONDO - CHÁCARA KLABIN', 'ViaMobilidade / Metrô-SP', ST_GeomFromText('LINESTRING(-46.630730 -23.592569, -46.631952 -23.594427, -46.633400 -23.596600, -46.635206 -23.598095, -46.636353 -23.598399, -46.638990 -23.598669, -46.645308 -23.598491, -46.651367 -23.597919, -46.655374 -23.597873, -46.657671 -23.599097, -46.660800 -23.602129, -46.662705 -23.604073, -46.663831 -23.605113, -46.666023 -23.607408, -46.668040 -23.609335, -46.669438 -23.610416, -46.671588 -23.611466, -46.674661 -23.612500, -46.676366 -23.613054, -46.678358 -23.613934, -46.679944 -23.615741, -46.680677 -23.616725, -46.682524 -23.618897, -46.684200 -23.621513, -46.685958 -23.623880, -46.688107 -23.626775, -46.688921 -23.627937, -46.690835 -23.630786, -46.692096 -23.632401, -46.692988 -23.633299, -46.693749 -23.634136, -46.696139 -23.636732, -46.697717 -23.639097, -46.698535 -23.640336, -46.699467 -23.641755, -46.699977 -23.642703, -46.701260 -23.644915, -46.702774 -23.647325, -46.704187 -23.650008, -46.704786 -23.650912, -46.705860 -23.652429, -46.706971 -23.653783, -46.708477 -23.654178, -46.712836 -23.654800, -46.714422 -23.654895, -46.715759 -23.654948, -46.719089 -23.655493, -46.720465 -23.655592, -46.722324 -23.655769, -46.726311 -23.654439, -46.726993 -23.652249, -46.726901 -23.648270, -46.728278 -23.645058, -46.732038 -23.644112, -46.733981 -23.643993, -46.735103 -23.643650, -46.736209 -23.642899, -46.736768 -23.641835, -46.737284 -23.640031, -46.737824 -23.639081, -46.739565 -23.637999, -46.742603 -23.638607, -46.744634 -23.639441, -46.745838 -23.640285, -46.746549 -23.641422, -46.746994 -23.642351, -46.748195 -23.643759, -46.749631 -23.644686, -46.752060 -23.645628, -46.754220 -23.645726, -46.756486 -23.646175, -46.757884 -23.647254, -46.758614 -23.648485, -46.758953 -23.649323, -46.759502 -23.650009, -46.761057 -23.651212, -46.763073 -23.652856, -46.764780 -23.654638, -46.766663 -23.657154, -46.768730 -23.660010)', 4326, 'axis-order=long-lat')),
(6, 6, 'L07', 'CPTM L07 — JUNDIAI - LUZ', 'CPTM', ST_GeomFromText('LINESTRING(-46.635349 -23.535167, -46.640298 -23.532890, -46.644405 -23.528246, -46.649520 -23.527923, -46.664421 -23.525499, -46.671748 -23.524979, -46.677557 -23.524559, -46.682889 -23.522316, -46.693218 -23.521368, -46.707557 -23.516016, -46.715026 -23.504530, -46.717120 -23.497314, -46.723984 -23.490130, -46.727418 -23.487472, -46.733806 -23.479615, -46.739971 -23.472196, -46.745732 -23.468066, -46.744632 -23.464271, -46.738246 -23.458857, -46.738753 -23.455134, -46.742512 -23.450781, -46.743011 -23.443351, -46.746923 -23.439441, -46.747748 -23.434675, -46.745884 -23.428827, -46.743631 -23.423359, -46.745010 -23.417358, -46.746227 -23.412690, -46.751427 -23.408246, -46.753583 -23.405043, -46.756508 -23.399956, -46.758131 -23.396348, -46.756672 -23.389871, -46.754846 -23.386340, -46.755514 -23.381073, -46.755604 -23.375223, -46.755380 -23.370408, -46.752209 -23.366616, -46.748661 -23.363419, -46.746049 -23.360189, -46.743433 -23.357688, -46.739885 -23.348655, -46.738387 -23.344038, -46.736178 -23.338553, -46.730052 -23.333281, -46.726765 -23.330466, -46.723991 -23.324488, -46.722088 -23.318106, -46.719832 -23.315459, -46.720628 -23.312056, -46.725055 -23.308927, -46.729454 -23.304516, -46.732724 -23.300038, -46.736519 -23.296551, -46.739150 -23.290845, -46.742322 -23.284104, -46.743052 -23.277173, -46.745589 -23.275002, -46.749488 -23.273830, -46.751440 -23.267614, -46.751810 -23.263153, -46.758819 -23.262318, -46.761981 -23.259447, -46.763774 -23.249955, -46.764114 -23.244278, -46.765195 -23.238818, -46.767556 -23.235891, -46.767880 -23.229593, -46.775078 -23.222529, -46.778291 -23.215156, -46.782635 -23.209490, -46.788313 -23.202821, -46.794271 -23.200894, -46.802631 -23.206207, -46.811163 -23.207554, -46.815823 -23.201093, -46.831895 -23.209805, -46.844650 -23.203176, -46.859918 -23.204454, -46.872554 -23.194743)', 4326, 'axis-order=long-lat')),
(7, 6, 'L08', 'CPTM L08 — AMADOR BUENO - JULIO PRESTES', 'CPTM', ST_GeomFromText('LINESTRING(-46.640735 -23.533024, -46.641882 -23.530952, -46.643309 -23.529348, -46.645866 -23.528546, -46.652102 -23.528426, -46.660427 -23.526236, -46.673401 -23.525071, -46.678582 -23.524757, -46.680077 -23.524220, -46.683300 -23.522651, -46.688647 -23.522260, -46.696689 -23.521080, -46.705163 -23.517312, -46.706267 -23.517191, -46.708937 -23.518651, -46.714540 -23.520053, -46.716851 -23.519150, -46.718553 -23.518692, -46.720130 -23.518754, -46.726635 -23.519100, -46.731089 -23.519388, -46.734392 -23.521144, -46.739179 -23.524955, -46.744427 -23.529118, -46.746661 -23.530518, -46.750230 -23.530790, -46.754036 -23.529812, -46.757251 -23.528648, -46.759504 -23.529251, -46.763780 -23.533024, -46.767575 -23.532698, -46.770946 -23.531406, -46.774704 -23.528566, -46.780001 -23.525235, -46.784818 -23.523736, -46.789544 -23.523810, -46.792002 -23.525894, -46.796512 -23.525602, -46.801631 -23.524827, -46.805691 -23.522851, -46.809507 -23.523065, -46.817446 -23.523365, -46.823062 -23.522411, -46.826814 -23.521587, -46.831124 -23.520645, -46.836307 -23.517855, -46.842499 -23.516233, -46.848128 -23.516606, -46.855958 -23.517958, -46.860497 -23.515959, -46.866969 -23.510288, -46.870670 -23.510633, -46.875556 -23.512649, -46.880894 -23.512198, -46.887269 -23.510229, -46.889249 -23.513825, -46.890031 -23.518039, -46.893289 -23.522477, -46.897374 -23.526503, -46.902869 -23.527901, -46.911356 -23.530602, -46.916158 -23.529208, -46.921249 -23.529879, -46.924168 -23.535008, -46.928452 -23.535280, -46.930778 -23.534656, -46.933425 -23.538697, -46.935105 -23.545306, -46.937119 -23.547658, -46.943226 -23.546043, -46.950497 -23.544086, -46.955257 -23.543778, -46.959630 -23.541483, -46.965225 -23.538274, -46.964781 -23.533804, -46.967847 -23.532301, -46.972773 -23.530189, -46.976077 -23.528028, -46.980586 -23.528565, -46.984037 -23.530688)', 4326, 'axis-order=long-lat')),
(8, 6, 'L09', 'CPTM L09 — VARGINHA - OSASCO', 'CPTM', ST_GeomFromText('LINESTRING(-46.776038 -23.527618, -46.772466 -23.530318, -46.769648 -23.531932, -46.765927 -23.533275, -46.761740 -23.531195, -46.759497 -23.529443, -46.756293 -23.529095, -46.753705 -23.530152, -46.749828 -23.530985, -46.747499 -23.531192, -46.745608 -23.532249, -46.744197 -23.535641, -46.740223 -23.539539, -46.734192 -23.544828, -46.730326 -23.548337, -46.727185 -23.550008, -46.717995 -23.554543, -46.713063 -23.556975, -46.708934 -23.558960, -46.705726 -23.561181, -46.704225 -23.563347, -46.702734 -23.567304, -46.700981 -23.571710, -46.699499 -23.573020, -46.697491 -23.574636, -46.695853 -23.576621, -46.693479 -23.580740, -46.691433 -23.584417, -46.690997 -23.586245, -46.691034 -23.588118, -46.691865 -23.590645, -46.692747 -23.593697, -46.692784 -23.595663, -46.693617 -23.597988, -46.694984 -23.599888, -46.696213 -23.603115, -46.697220 -23.605929, -46.698355 -23.610531, -46.699200 -23.614377, -46.699919 -23.617086, -46.700397 -23.618294, -46.700672 -23.620121, -46.701419 -23.621340, -46.702481 -23.622419, -46.704163 -23.623506, -46.708867 -23.625149, -46.710069 -23.625824, -46.711509 -23.627017, -46.716394 -23.632213, -46.718931 -23.634926, -46.722240 -23.638472, -46.724515 -23.641200, -46.725717 -23.643774, -46.725968 -23.644949, -46.725380 -23.648289, -46.724554 -23.649957, -46.721298 -23.653703, -46.718838 -23.656483, -46.715360 -23.658906, -46.713364 -23.660372, -46.711526 -23.662405, -46.710353 -23.664539, -46.708187 -23.667755, -46.704021 -23.674483, -46.701388 -23.678447, -46.698374 -23.681643, -46.695456 -23.687194, -46.692794 -23.689541, -46.686709 -23.692871, -46.685693 -23.697286, -46.687475 -23.703318, -46.688451 -23.706410, -46.690374 -23.712494, -46.691994 -23.717756, -46.691773 -23.722944, -46.692067 -23.729836, -46.696756 -23.736023, -46.709419 -23.754696, -46.711975 -23.764203, -46.712005 -23.771391)', 4326, 'axis-order=long-lat')),
(9, 4, '875A-10', 'Aeroporto - Perdizes', 'SPTrans', ST_GeomFromText('LINESTRING(-46.681166 -23.536022, -46.676203 -23.533774, -46.672602 -23.536167, -46.667417 -23.533952, -46.662815 -23.533648, -46.660973 -23.532072, -46.657769 -23.532647, -46.649037 -23.537870, -46.648390 -23.539204, -46.647714 -23.540756, -46.647546 -23.540713, -46.647620 -23.540468, -46.648276 -23.538891, -46.648643 -23.540012, -46.646833 -23.541774, -46.644358 -23.541096, -46.644313 -23.544253, -46.645267 -23.546551, -46.647316 -23.547270, -46.650568 -23.548335, -46.654625 -23.550221, -46.660584 -23.553654, -46.663419 -23.555964, -46.665464 -23.556564, -46.666048 -23.557072, -46.664077 -23.556475, -46.662890 -23.555997, -46.660281 -23.558174, -46.656208 -23.561770, -46.649032 -23.567722, -46.642812 -23.572876, -46.641039 -23.576672, -46.639980 -23.579107, -46.638256 -23.581828, -46.636919 -23.583923, -46.635198 -23.586748, -46.634698 -23.588869, -46.635751 -23.591260, -46.636658 -23.592737, -46.636754 -23.597857, -46.636832 -23.604320, -46.637930 -23.608538, -46.638011 -23.612288, -46.638837 -23.616416, -46.640554 -23.624253, -46.641381 -23.626549, -46.644283 -23.628238, -46.647583 -23.626194, -46.649482 -23.621593, -46.651387 -23.617571, -46.655865 -23.615072, -46.657208 -23.612687, -46.654201 -23.609766, -46.652947 -23.607904, -46.655621 -23.610683, -46.658756 -23.614141, -46.662120 -23.618169, -46.661795 -23.624439, -46.661890 -23.625796, -46.661962 -23.627694, -46.664486 -23.628731, -46.667119 -23.629323, -46.668539 -23.630254, -46.669275 -23.631690, -46.669881 -23.633494, -46.669214 -23.633706, -46.668813 -23.631025, -46.667696 -23.629688, -46.663610 -23.631020, -46.660085 -23.632793, -46.660587 -23.634566, -46.659124 -23.634975, -46.657903 -23.635757, -46.658146 -23.638481, -46.660342 -23.639238, -46.662441 -23.637978, -46.662005 -23.640322, -46.660791 -23.642099, -46.661601 -23.642873, -46.662877 -23.643439)', 4326, 'axis-order=long-lat')),
(10, 4, '702U-22', 'Metrô Butantã - Term. Pq. D. Pedro Ii', 'SPTrans', ST_GeomFromText('LINESTRING(-46.630676 -23.546823, -46.630342 -23.547279, -46.630131 -23.547582, -46.629849 -23.547977, -46.629670 -23.548137, -46.629788 -23.548416, -46.629229 -23.549206, -46.628466 -23.549420, -46.627963 -23.549308, -46.627414 -23.548936, -46.626984 -23.548397, -46.626811 -23.547806, -46.626562 -23.546146, -46.626545 -23.545436, -46.626713 -23.544662, -46.626935 -23.544094, -46.627026 -23.543517, -46.627061 -23.542804, -46.627327 -23.542264, -46.628465 -23.541300, -46.629855 -23.540086, -46.632073 -23.539462, -46.632815 -23.539284, -46.634040 -23.539255, -46.635461 -23.538931, -46.636230 -23.539011, -46.636365 -23.539647, -46.638802 -23.541222, -46.639849 -23.542055, -46.641030 -23.543017, -46.641696 -23.543510, -46.642694 -23.544291, -46.643550 -23.544952, -46.645165 -23.546430, -46.645455 -23.546759, -46.646269 -23.547155, -46.647316 -23.547270, -46.648545 -23.547646, -46.649297 -23.547923, -46.651930 -23.548768, -46.653825 -23.549757, -46.655291 -23.550595, -46.659108 -23.552647, -46.660991 -23.553997, -46.662565 -23.555280, -46.663206 -23.555809, -46.663935 -23.556216, -46.664897 -23.556429, -46.665598 -23.556614, -46.666379 -23.557002, -46.667913 -23.558079, -46.668617 -23.558558, -46.670621 -23.559657, -46.672483 -23.560697, -46.674714 -23.562061, -46.676506 -23.563403, -46.677614 -23.564028, -46.679747 -23.565140, -46.683849 -23.567317, -46.686395 -23.568662, -46.689927 -23.570500, -46.691054 -23.571000, -46.691840 -23.571063, -46.693946 -23.571281, -46.695255 -23.571487, -46.696256 -23.571577, -46.700160 -23.572083, -46.701566 -23.572287, -46.702416 -23.572197, -46.703126 -23.572122, -46.703797 -23.572303, -46.704258 -23.572405, -46.704707 -23.572396, -46.706132 -23.571870, -46.707733 -23.571445, -46.708199 -23.572471, -46.709259 -23.572137, -46.709393 -23.571612, -46.708160 -23.571435, -46.708331 -23.571941)', 4326, 'axis-order=long-lat')),
(11, 4, '177Y-10', 'Metrô Barra Funda - Pinheiros', 'SPTrans', ST_GeomFromText('LINESTRING(-46.701092 -23.565906, -46.701151 -23.566896, -46.701146 -23.567357, -46.700779 -23.567580, -46.700530 -23.567702, -46.700124 -23.567864, -46.699362 -23.567720, -46.696514 -23.567609, -46.695909 -23.567622, -46.694914 -23.567572, -46.693569 -23.567166, -46.692479 -23.566535, -46.689463 -23.564730, -46.687533 -23.563573, -46.685004 -23.562059, -46.682844 -23.560762, -46.681583 -23.560020, -46.681147 -23.559529, -46.681610 -23.558663, -46.681902 -23.558145, -46.682438 -23.557361, -46.682735 -23.556605, -46.682520 -23.556266, -46.682317 -23.556035, -46.681700 -23.555633, -46.681071 -23.555208, -46.680349 -23.554616, -46.678687 -23.552834, -46.678185 -23.552208, -46.677859 -23.551762, -46.677582 -23.551335, -46.677159 -23.550359, -46.676982 -23.549554, -46.676892 -23.548407, -46.676652 -23.545853, -46.676502 -23.544282, -46.676334 -23.542542, -46.676087 -23.541603, -46.675854 -23.541029, -46.674918 -23.539277, -46.674471 -23.538443, -46.674323 -23.537934, -46.674256 -23.537309, -46.674122 -23.535532, -46.674109 -23.535164, -46.674158 -23.534802, -46.674261 -23.534438, -46.674456 -23.534017, -46.674871 -23.533320, -46.675351 -23.532525, -46.675628 -23.532257, -46.676529 -23.531733, -46.676896 -23.531427, -46.677160 -23.530717, -46.677262 -23.530309, -46.677223 -23.530150, -46.676966 -23.529675, -46.676381 -23.529137, -46.675726 -23.528636, -46.674775 -23.528024, -46.674339 -23.527833, -46.674274 -23.527956, -46.673910 -23.528221, -46.673415 -23.527464, -46.673275 -23.527350, -46.673015 -23.527221, -46.672760 -23.527189, -46.672632 -23.527070, -46.672076 -23.526326, -46.671803 -23.526010, -46.670818 -23.525721, -46.669647 -23.525891, -46.669208 -23.526134, -46.668879 -23.526358, -46.668518 -23.526563, -46.667990 -23.526625, -46.667195 -23.526674, -46.666709 -23.526709, -46.666779 -23.527387, -46.666833 -23.527919)', 4326, 'axis-order=long-lat')),
(12, 4, '917H-10', 'Term. Pirituba - Metrô Vl. Mariana', 'SPTrans', ST_GeomFromText('LINESTRING(-46.634266 -23.589508, -46.634512 -23.587950, -46.637923 -23.581999, -46.640435 -23.578055, -46.641593 -23.575001, -46.645516 -23.570238, -46.657983 -23.560011, -46.663163 -23.555365, -46.665175 -23.555800, -46.666425 -23.555839, -46.673652 -23.552855, -46.677924 -23.550651, -46.680238 -23.549650, -46.683855 -23.549535, -46.685134 -23.548585, -46.687469 -23.547514, -46.689147 -23.547414, -46.691520 -23.545917, -46.694440 -23.543632, -46.696458 -23.542000, -46.699086 -23.541041, -46.704101 -23.540204, -46.705671 -23.539563, -46.705532 -23.539653, -46.707964 -23.538611, -46.709406 -23.536991, -46.710269 -23.535827, -46.714325 -23.535386, -46.713854 -23.536442, -46.714441 -23.537531, -46.714083 -23.539033, -46.713408 -23.539609, -46.716100 -23.540805, -46.718259 -23.540124, -46.719247 -23.538730, -46.719522 -23.537951, -46.720205 -23.537157, -46.723535 -23.536926, -46.725918 -23.536722, -46.730970 -23.530875, -46.737001 -23.530948, -46.740351 -23.527260, -46.741124 -23.524551, -46.740804 -23.522035, -46.742753 -23.520256, -46.746113 -23.520244, -46.750084 -23.520723, -46.752237 -23.520369, -46.753216 -23.517097, -46.754091 -23.511800, -46.753560 -23.508992, -46.751571 -23.508210, -46.748077 -23.507877, -46.746688 -23.507149, -46.747204 -23.506369, -46.747118 -23.505485, -46.746577 -23.504407, -46.746447 -23.501094, -46.746172 -23.499532, -46.745847 -23.496385, -46.747600 -23.494950, -46.749114 -23.494101, -46.749107 -23.493088, -46.749701 -23.489626, -46.748265 -23.488020, -46.747214 -23.486274, -46.745060 -23.484870, -46.744006 -23.484356, -46.742563 -23.484167, -46.739492 -23.485974, -46.736284 -23.487245, -46.733387 -23.488053, -46.730461 -23.488294, -46.727874 -23.488292, -46.724850 -23.485860, -46.725128 -23.485631, -46.727130 -23.486559, -46.726869 -23.486677, -46.726222 -23.485989, -46.725773 -23.486038)', 4326, 'axis-order=long-lat')),
(13, 4, '675A-10', 'Pq. Sto. Antonio - Metrô São Judas', 'SPTrans', ST_GeomFromText('LINESTRING(-46.756079 -23.662359, -46.755602 -23.661972, -46.754553 -23.661260, -46.753094 -23.661674, -46.752448 -23.661918, -46.749815 -23.661599, -46.747917 -23.661064, -46.745907 -23.660090, -46.743416 -23.659113, -46.742009 -23.657717, -46.741177 -23.655475, -46.741130 -23.653879, -46.739820 -23.653066, -46.736166 -23.653333, -46.734460 -23.653172, -46.733790 -23.651495, -46.733374 -23.650321, -46.731906 -23.648389, -46.730101 -23.646029, -46.729810 -23.644803, -46.726314 -23.644732, -46.720535 -23.644886, -46.717635 -23.644950, -46.715691 -23.641603, -46.715233 -23.637042, -46.714683 -23.636093, -46.713943 -23.635386, -46.715087 -23.635650, -46.717589 -23.634378, -46.711461 -23.627674, -46.708281 -23.629697, -46.707069 -23.631913, -46.703766 -23.634332, -46.702502 -23.634676, -46.701001 -23.635922, -46.697109 -23.638273, -46.694465 -23.636171, -46.691449 -23.631855, -46.690251 -23.630471, -46.687652 -23.626845, -46.686101 -23.627339, -46.685291 -23.628955, -46.685625 -23.629368, -46.685951 -23.629041, -46.683378 -23.626185, -46.679916 -23.622490, -46.677334 -23.619754, -46.673249 -23.620987, -46.669822 -23.623727, -46.665985 -23.626226, -46.664628 -23.626870, -46.662508 -23.627947, -46.663702 -23.628335, -46.665443 -23.628967, -46.667484 -23.629445, -46.668539 -23.630254, -46.669128 -23.631296, -46.669488 -23.632561, -46.668948 -23.632902, -46.668813 -23.631025, -46.668157 -23.630000, -46.666490 -23.629642, -46.666393 -23.629373, -46.662789 -23.628434, -46.661501 -23.627474, -46.661459 -23.625391, -46.661711 -23.622191, -46.661971 -23.618028, -46.660152 -23.615794, -46.655517 -23.610977, -46.653860 -23.609397, -46.651708 -23.610360, -46.649905 -23.614677, -46.646665 -23.622507, -46.644319 -23.628162, -46.641538 -23.626869, -46.639763 -23.625619, -46.640406 -23.624258, -46.641111 -23.626052, -46.642102 -23.627005)', 4326, 'axis-order=long-lat')),
(14, 4, '509M-10', 'Jd. Miriam - Term. Princ. Isabel', 'SPTrans', ST_GeomFromText('LINESTRING(-46.644673 -23.534294, -46.645147 -23.534332, -46.643801 -23.534720, -46.640368 -23.539420, -46.638465 -23.541926, -46.637848 -23.542591, -46.637080 -23.542985, -46.636156 -23.542347, -46.635782 -23.541358, -46.634569 -23.541347, -46.634939 -23.542259, -46.636027 -23.543997, -46.638988 -23.548424, -46.638416 -23.550047, -46.637051 -23.551964, -46.636754 -23.553394, -46.637711 -23.556114, -46.639155 -23.559431, -46.640809 -23.565235, -46.640942 -23.569585, -46.641426 -23.574966, -46.643073 -23.576288, -46.647978 -23.579781, -46.651222 -23.581948, -46.653250 -23.583355, -46.654805 -23.583298, -46.655839 -23.582216, -46.656866 -23.580682, -46.657666 -23.581954, -46.657105 -23.582618, -46.655923 -23.584969, -46.654121 -23.586599, -46.652946 -23.587749, -46.652122 -23.589742, -46.651596 -23.591614, -46.652661 -23.593414, -46.656732 -23.597693, -46.661968 -23.603235, -46.664210 -23.605600, -46.668524 -23.610210, -46.671348 -23.613227, -46.676170 -23.618368, -46.679419 -23.621789, -46.682693 -23.625226, -46.684735 -23.627247, -46.684923 -23.628327, -46.684778 -23.629594, -46.682988 -23.631428, -46.680300 -23.633545, -46.678034 -23.636065, -46.676866 -23.639093, -46.675734 -23.641218, -46.673210 -23.643592, -46.672138 -23.644955, -46.671113 -23.646766, -46.669640 -23.651183, -46.668745 -23.653380, -46.667227 -23.654690, -46.665436 -23.656733, -46.663384 -23.659098, -46.663341 -23.660773, -46.662907 -23.661848, -46.661401 -23.663634, -46.659794 -23.664560, -46.655742 -23.666497, -46.653312 -23.667614, -46.649850 -23.669030, -46.646494 -23.671253, -46.644268 -23.672894, -46.643055 -23.674236, -46.641732 -23.677136, -46.640804 -23.678744, -46.639325 -23.680446, -46.637630 -23.681655, -46.637385 -23.682652, -46.637128 -23.681790, -46.637564 -23.680825, -46.637314 -23.680227, -46.636381 -23.679708, -46.636164 -23.679597)', 4326, 'axis-order=long-lat')),
(15, 4, '5154-10', 'Term. Sto. Amaro - Term. Princ. Isabel', 'SPTrans', ST_GeomFromText('LINESTRING(-46.645036 -23.534355, -46.644546 -23.533961, -46.643851 -23.534751, -46.645260 -23.534375, -46.643273 -23.533541, -46.640340 -23.535086, -46.637935 -23.535157, -46.636813 -23.534726, -46.634809 -23.534845, -46.634784 -23.538509, -46.635621 -23.541014, -46.634569 -23.541347, -46.634848 -23.542138, -46.635772 -23.543513, -46.638562 -23.547880, -46.638942 -23.549128, -46.639794 -23.550909, -46.638694 -23.552228, -46.638637 -23.554093, -46.639889 -23.556367, -46.641539 -23.558297, -46.645034 -23.562402, -46.647347 -23.565114, -46.649476 -23.568198, -46.653552 -23.572050, -46.656370 -23.574629, -46.657066 -23.576711, -46.656900 -23.578299, -46.656503 -23.580459, -46.657980 -23.581768, -46.657327 -23.582275, -46.656440 -23.583904, -46.655491 -23.585564, -46.653775 -23.586871, -46.652626 -23.588464, -46.652122 -23.589742, -46.651561 -23.591454, -46.652303 -23.592925, -46.654989 -23.595835, -46.659753 -23.600852, -46.662866 -23.604182, -46.665689 -23.607184, -46.670975 -23.607125, -46.674370 -23.604418, -46.675297 -23.605074, -46.676693 -23.608517, -46.677477 -23.610893, -46.678281 -23.613080, -46.679891 -23.612991, -46.684595 -23.609226, -46.690008 -23.604913, -46.691928 -23.603376, -46.693050 -23.605504, -46.694345 -23.609063, -46.695796 -23.613067, -46.696943 -23.616167, -46.698003 -23.619113, -46.698928 -23.621576, -46.700228 -23.624241, -46.702386 -23.625097, -46.704382 -23.628022, -46.707312 -23.632279, -46.703571 -23.634374, -46.702502 -23.634676, -46.701001 -23.635922, -46.697961 -23.637774, -46.698494 -23.640705, -46.700913 -23.643618, -46.704785 -23.649109, -46.707109 -23.650442, -46.710921 -23.651539, -46.712797 -23.651572, -46.715302 -23.651406, -46.716753 -23.654194, -46.716663 -23.655195, -46.715056 -23.654670, -46.712826 -23.654320, -46.711948 -23.654305, -46.711152 -23.654199, -46.710618 -23.654157)', 4326, 'axis-order=long-lat')),
(16, 4, '107T-10', 'Metrô Tucuruvi - Term. Pinheiros', 'SPTrans', ST_GeomFromText('LINESTRING(-46.701459 -23.566203, -46.701257 -23.566516, -46.701253 -23.566673, -46.701495 -23.566879, -46.701279 -23.567279, -46.700358 -23.567776, -46.696514 -23.567609, -46.694106 -23.567496, -46.692523 -23.568434, -46.690856 -23.571152, -46.690098 -23.572380, -46.687767 -23.576025, -46.685713 -23.579352, -46.684739 -23.581262, -46.683834 -23.582108, -46.684599 -23.580522, -46.681964 -23.578774, -46.678318 -23.575462, -46.674753 -23.572049, -46.670833 -23.568293, -46.667960 -23.565536, -46.664995 -23.562700, -46.658973 -23.556949, -46.655805 -23.553982, -46.649579 -23.551076, -46.647459 -23.547496, -46.646064 -23.547318, -46.642864 -23.547955, -46.641935 -23.547834, -46.641097 -23.547666, -46.639827 -23.547411, -46.638769 -23.545941, -46.638197 -23.545002, -46.638153 -23.543513, -46.638711 -23.543165, -46.638665 -23.542896, -46.637922 -23.542514, -46.637694 -23.542837, -46.636712 -23.542948, -46.635947 -23.543153, -46.635460 -23.543625, -46.634703 -23.542561, -46.633735 -23.539616, -46.633558 -23.537015, -46.633114 -23.535278, -46.632540 -23.532795, -46.631441 -23.529258, -46.630560 -23.527157, -46.629441 -23.525854, -46.628344 -23.525221, -46.625278 -23.524224, -46.625183 -23.520571, -46.625036 -23.516598, -46.624932 -23.512878, -46.624834 -23.509281, -46.624674 -23.504187, -46.624584 -23.501854, -46.618604 -23.501088, -46.615718 -23.500860, -46.614991 -23.500230, -46.615532 -23.498916, -46.615688 -23.497653, -46.615208 -23.495949, -46.617200 -23.493255, -46.618406 -23.491344, -46.619048 -23.489175, -46.619047 -23.487024, -46.616768 -23.486085, -46.612644 -23.481615, -46.611521 -23.480994, -46.611230 -23.480430, -46.610864 -23.479726, -46.608642 -23.478971, -46.607324 -23.480091, -46.605797 -23.480680, -46.606043 -23.482053, -46.605707 -23.482330, -46.603750 -23.482104, -46.603425 -23.481539, -46.604206 -23.480811)', 4326, 'axis-order=long-lat')),
(17, 4, '930P-10', 'Term. Pq. D. Pedro Ii - Term. Pinheiros', 'SPTrans', ST_GeomFromText('LINESTRING(-46.630387 -23.546497, -46.630069 -23.546975, -46.629754 -23.547461, -46.629448 -23.548012, -46.629779 -23.548303, -46.629408 -23.549145, -46.630347 -23.549588, -46.631481 -23.550087, -46.631787 -23.550073, -46.631990 -23.549739, -46.632999 -23.549488, -46.633163 -23.549429, -46.633055 -23.548969, -46.633179 -23.548367, -46.633227 -23.547866, -46.633328 -23.547256, -46.633610 -23.545400, -46.633770 -23.544928, -46.633952 -23.544651, -46.634206 -23.544352, -46.634574 -23.544173, -46.634719 -23.544249, -46.635411 -23.545024, -46.636030 -23.546056, -46.636791 -23.547386, -46.638644 -23.546030, -46.638434 -23.545614, -46.638197 -23.545002, -46.638048 -23.543691, -46.638195 -23.543455, -46.638595 -23.543230, -46.638781 -23.543166, -46.641030 -23.543017, -46.641696 -23.543510, -46.642694 -23.544291, -46.643273 -23.544976, -46.642930 -23.546915, -46.642723 -23.547851, -46.643157 -23.548263, -46.645103 -23.549627, -46.646441 -23.550060, -46.649579 -23.551076, -46.654145 -23.552823, -46.656323 -23.554464, -46.657494 -23.555570, -46.660281 -23.558174, -46.663916 -23.561649, -46.665497 -23.563216, -46.667960 -23.565536, -46.670027 -23.567522, -46.671935 -23.569346, -46.673211 -23.570568, -46.676218 -23.573453, -46.678107 -23.575261, -46.681032 -23.578067, -46.681964 -23.578774, -46.684165 -23.580229, -46.684769 -23.580618, -46.685625 -23.579147, -46.686844 -23.577152, -46.687615 -23.575913, -46.688635 -23.574255, -46.690022 -23.572042, -46.690689 -23.570949, -46.691609 -23.569501, -46.692828 -23.567780, -46.693569 -23.567166, -46.694235 -23.566552, -46.694439 -23.565764, -46.694498 -23.564980, -46.695514 -23.564985, -46.696248 -23.565267, -46.698033 -23.565391, -46.699151 -23.565301, -46.701054 -23.565042, -46.701155 -23.565886, -46.701954 -23.565793, -46.702220 -23.565824, -46.702208 -23.565949, -46.702014 -23.566228)', 4326, 'axis-order=long-lat')),
(18, 4, '2002-10', 'Term. Pq. D. Pedro Ii - Term. Bandeira', 'SPTrans', ST_GeomFromText('LINESTRING(-46.629633 -23.547164, -46.629298 -23.547629, -46.629730 -23.548189, -46.629701 -23.548546, -46.630018 -23.549443, -46.631330 -23.550035, -46.631787 -23.550073, -46.631990 -23.549739, -46.633066 -23.549485, -46.633193 -23.549406, -46.632981 -23.548815, -46.633223 -23.548180, -46.633264 -23.547636, -46.633527 -23.545895, -46.633673 -23.545077, -46.633952 -23.544651, -46.634206 -23.544352, -46.634596 -23.544174, -46.634817 -23.544376, -46.635521 -23.545167, -46.636491 -23.546885, -46.637848 -23.546621, -46.638525 -23.545711, -46.638126 -23.545056, -46.638048 -23.543691, -46.638195 -23.543455, -46.638680 -23.543182, -46.638998 -23.543044, -46.641174 -23.542961, -46.641509 -23.542775, -46.642976 -23.542559, -46.644404 -23.543803, -46.643550 -23.544952, -46.643021 -23.545985, -46.642596 -23.547883, -46.642357 -23.549010, -46.642173 -23.549823, -46.641318 -23.550208, -46.640186 -23.549666, -46.639924 -23.550066, -46.639596 -23.550187, -46.639273 -23.550150, -46.639104 -23.549970, -46.639035 -23.549456, -46.639110 -23.549179, -46.639335 -23.549280, -46.639779 -23.549331, -46.640044 -23.549359, -46.640321 -23.549711, -46.641999 -23.550513, -46.641703 -23.550809, -46.638694 -23.552228, -46.636342 -23.552152, -46.635049 -23.551822, -46.634219 -23.552070, -46.633269 -23.552474, -46.632531 -23.551728, -46.631962 -23.550678, -46.631123 -23.550074, -46.629394 -23.549417, -46.628578 -23.549426, -46.627963 -23.549308, -46.627316 -23.548988, -46.626013 -23.548143, -46.624316 -23.547120, -46.621881 -23.545935, -46.622365 -23.544515, -46.624650 -23.544520, -46.626603 -23.544468, -46.626834 -23.543675, -46.627369 -23.543201, -46.628006 -23.543073, -46.628783 -23.543241, -46.629258 -23.543537, -46.630483 -23.544841, -46.631011 -23.545286, -46.630969 -23.546007, -46.630457 -23.545961, -46.629867 -23.546831, -46.629554 -23.547274)', 4326, 'axis-order=long-lat'));

-- -----------------------------------------------------------------------------
-- usuario — SIMULADO (LGPD; nomes fake)
-- -----------------------------------------------------------------------------
INSERT INTO usuario (id_usuario, nome, email, cpf_hash, data_nascimento, id_modal_preferido, criado_em, ativo) VALUES
(1, 'Ana Fictícia Silva', 'ana.ficticia@exemplo.sp.br', SHA2('CPF-FAKE-11111111111', 256), '1992-04-12', 5, '2025-08-01 10:00:00', TRUE),
(2, 'Bruno Teste Oliveira', 'bruno.teste@exemplo.sp.br', SHA2('CPF-FAKE-22222222222', 256), '1988-11-03', 2, '2025-09-15 14:30:00', TRUE),
(3, 'Carla Demo Souza', 'carla.demo@exemplo.sp.br', SHA2('CPF-FAKE-33333333333', 256), '1995-07-22', 4, '2025-10-01 09:15:00', TRUE),
(4, 'Diego Mock Pereira', 'diego.mock@exemplo.sp.br', SHA2('CPF-FAKE-44444444444', 256), '1990-01-30', 7, '2025-10-20 16:45:00', TRUE),
(5, 'Elena Sample Costa', 'elena.sample@exemplo.sp.br', SHA2('CPF-FAKE-55555555555', 256), '1998-12-08', 5, '2026-01-05 11:20:00', TRUE);

-- -----------------------------------------------------------------------------
-- viagem / trecho — SIMULADO sobre locais/linhas reais; distância haversine
-- -----------------------------------------------------------------------------
INSERT INTO viagem (id_viagem, id_usuario, id_local_origem, id_local_destino, inicio, fim, status) VALUES
(1, 1, 10, 1, '2026-11-17 12:00:00', '2026-11-17 12:55:00', 'concluida'),
(2, 2, 7, 2, '2026-11-17 13:10:00', '2026-11-17 13:50:00', 'concluida'),
(3, 3, 1, 4, '2026-11-18 11:00:00', '2026-11-18 11:45:00', 'concluida'),
(4, 4, 10, 7, '2026-11-18 12:00:00', '2026-11-18 12:40:00', 'concluida'),
(5, 5, 5, 4, '2026-11-18 07:30:00', '2026-11-18 08:05:00', 'concluida'),
(6, 1, 1, 7, '2026-11-18 18:00:00', NULL, 'em_curso'),
(7, 2, 3, 4, '2026-11-19 08:00:00', NULL, 'planejada');

INSERT INTO trecho_viagem (id_trecho, id_viagem, ordem, id_modal, id_linha, inicio, fim, distancia_km, geom_percurso) VALUES
(1, 1, 1, 2, NULL, '2026-11-17 12:00:00', '2026-11-17 12:20:00', 3.407, NULL),
(2, 1, 2, 5, 2, '2026-11-17 12:25:00', '2026-11-17 12:55:00', 2.869, NULL),
(3, 2, 1, 2, NULL, '2026-11-17 13:10:00', '2026-11-17 13:50:00', 3.775, NULL),
(4, 3, 1, 4, 10, '2026-11-18 11:00:00', '2026-11-18 11:45:00', 7.335, NULL),
(5, 4, 1, 7, NULL, '2026-11-18 12:00:00', '2026-11-18 12:40:00', 6.610, NULL),
(6, 5, 1, 5, 4, '2026-11-18 07:30:00', '2026-11-18 08:05:00', 7.766, NULL),
(7, 6, 1, 1, NULL, '2026-11-18 18:00:00', '2026-11-18 18:10:00', 1.166, NULL),
(8, 6, 2, 5, 1, '2026-11-18 18:15:00', '2026-11-18 18:40:00', 4.133, NULL);

INSERT INTO trecho_segmento (id_trecho, id_segmento, ordem) VALUES
(1, 1, 1),
(1, 2, 2),
(3, 1, 1),
(4, 1, 1),
(4, 2, 2),
(5, 3, 1),
(5, 4, 2),
(6, 2, 1),
(8, 3, 1);

-- -----------------------------------------------------------------------------
-- sugestao_modal — SIMULADO (conteúdo de negócio; linhas/modais reais)
-- -----------------------------------------------------------------------------
INSERT INTO sugestao_modal (id_sugestao, id_viagem, id_modal_sugerido, id_linha, distancia_estimada_km, duracao_estimada_min, motivo, gerada_em, aceita) VALUES
(1, 4, 5, 4, 6.279, 35, 'menor_co2', '2026-11-18 11:55:00', FALSE),
(2, 4, 2, NULL, 5.949, 40, 'congestionamento', '2026-11-18 11:56:00', FALSE),
(3, 7, 5, 4, 4.472, 28, 'menor_tempo', '2026-11-18 20:00:00', NULL),
(4, 3, 5, 2, 6.601, 30, 'menor_co2', '2026-11-18 10:50:00', TRUE),
(5, 2, 4, 9, 3.964, 45, 'congestionamento', '2026-11-17 13:00:00', TRUE);

SELECT 'Seed concluído (dados reais + simulados)' AS status;
SELECT 'usuario' AS tabela, COUNT(*) AS n FROM usuario
UNION ALL SELECT 'modal_transporte', COUNT(*) FROM modal_transporte
UNION ALL SELECT 'fonte_referencia', COUNT(*) FROM fonte_referencia
UNION ALL SELECT 'fator_emissao', COUNT(*) FROM fator_emissao
UNION ALL SELECT 'local', COUNT(*) FROM local
UNION ALL SELECT 'segmento_via', COUNT(*) FROM segmento_via
UNION ALL SELECT 'sensor', COUNT(*) FROM sensor
UNION ALL SELECT 'leitura_trafego', COUNT(*) FROM leitura_trafego
UNION ALL SELECT 'linha_transporte', COUNT(*) FROM linha_transporte
UNION ALL SELECT 'viagem', COUNT(*) FROM viagem
UNION ALL SELECT 'trecho_viagem', COUNT(*) FROM trecho_viagem
UNION ALL SELECT 'trecho_segmento', COUNT(*) FROM trecho_segmento
UNION ALL SELECT 'sugestao_modal', COUNT(*) FROM sugestao_modal;

-- Metadados da geração (comentário):
-- linhas GTFS: 18 | locais: 60 | segmentos OSM: 10
-- route_ids: METRÔ L1, METRÔ L2, METRÔ L3, METRÔ L4, METRÔ L5, CPTM L07, CPTM L08, CPTM L09, 875A-10, 702U-22, 177Y-10, 917H-10, 675A-10, 509M-10, 5154-10, 107T-10, 930P-10, 2002-10

-- ### FIM: 06_seed.sql ###


-- ##########################################################################
-- INÍCIO: 07_relatorios.sql
-- ##########################################################################

-- =============================================================================
-- 07_relatorios.sql – Consultas de relatório do projeto
-- =============================================================================

USE mobilidade_urbana;

SELECT '=== 1) CO₂ por usuário ===' AS relatorio;
SELECT id_usuario, nome, qtd_viagens, distancia_total_km, co2_total_g
FROM vw_emissao_usuario
ORDER BY co2_total_g DESC;

SELECT '=== 2) CO₂ por modal ===' AS relatorio;
SELECT codigo, nome, categoria, qtd_trechos, distancia_total_km, co2_total_g
FROM vw_emissao_modal
ORDER BY co2_total_g DESC;

SELECT '=== 3) CO₂ por linha/rota ===' AS relatorio;
SELECT codigo, nome, operadora, codigo_modal, qtd_trechos, distancia_total_km, co2_total_g
FROM vw_emissao_linha
ORDER BY co2_total_g DESC;

SELECT '=== 4) Economia vs carro (por trecho) ===' AS relatorio;
SELECT id_viagem, codigo_modal, distancia_km, co2_trecho_g, co2_se_carro_g, economia_vs_carro_g
FROM vw_economia_vs_carro
ORDER BY economia_vs_carro_g DESC;

SELECT '=== 5) Economia mensal por usuário ===' AS relatorio;
SELECT id_usuario, nome_usuario, ano_mes, qtd_viagens, distancia_km,
       co2_emitido_g, co2_se_carro_g, economia_vs_carro_g
FROM vw_economia_usuario_mes
ORDER BY ano_mes, economia_vs_carro_g DESC;

SELECT '=== 6) Ranking de congestionamento atual ===' AS relatorio;
SELECT id_segmento, nome_via, nivel_congestionamento, velocidade_media_kmh,
       volume_veiculos, registrado_em, possui_ciclovia, faixa_onibus
FROM vw_congestionamento_atual
ORDER BY nivel_congestionamento DESC, velocidade_media_kmh ASC;

SELECT '=== 7) Taxa de aceitação de sugestões ===' AS relatorio;
SELECT total_sugestoes, aceitas, recusadas, sem_resposta, taxa_aceitacao_pct
FROM vw_taxa_aceitacao_sugestao;

SELECT '=== 8) Emissão detalhada por trecho ===' AS relatorio;
SELECT id_viagem, ordem, codigo_modal, codigo_linha, distancia_km, g_co2_pkm, co2_trecho_g
FROM vw_emissao_trecho
ORDER BY id_viagem, ordem;

SELECT '=== 9) Top usuários por economia de CO₂ ===' AS relatorio;
SELECT
  u.id_usuario,
  u.nome,
  ROUND(SUM(ec.economia_vs_carro_g), 3) AS economia_total_g,
  ROUND(SUM(ec.economia_vs_carro_g) / 1000, 3) AS economia_total_kg
FROM usuario u
JOIN viagem v ON v.id_usuario = u.id_usuario AND v.status = 'concluida'
JOIN vw_economia_vs_carro ec ON ec.id_viagem = v.id_viagem
GROUP BY u.id_usuario, u.nome
ORDER BY economia_total_g DESC;

-- ### FIM: 07_relatorios.sql ###


-- ##########################################################################
-- INÍCIO: 08_testes.sql
-- ##########################################################################

-- =============================================================================
-- 08_testes.sql – Provas de constraints/triggers + rollback de transação
-- Cada caso negativo deve ser REJEITADO; T11 deve ser OK.
-- =============================================================================

USE mobilidade_urbana;
SET time_zone = '+00:00';

DROP TEMPORARY TABLE IF EXISTS tmp_resultado_teste;
CREATE TEMPORARY TABLE tmp_resultado_teste (
  id INT AUTO_INCREMENT PRIMARY KEY,
  teste VARCHAR(120) NOT NULL,
  esperado VARCHAR(40) NOT NULL,
  obtido VARCHAR(40) NOT NULL,
  detalhe VARCHAR(500) NULL
);

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_rodar_testes$$
CREATE PROCEDURE sp_rodar_testes()
BEGIN
  DECLARE v_msg TEXT DEFAULT NULL;
  DECLARE v_failed INT DEFAULT 0;

  -- T1: CHECK distancia_km > 0
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO trecho_viagem (id_viagem, ordem, id_modal, inicio, fim, distancia_km)
    VALUES (7, 99, 2, '2026-11-19 08:00:00', '2026-11-19 08:30:00', 0);
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T1 CHECK distancia_km > 0', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T1 CHECK distancia_km > 0', 'REJEITADO', 'ACEITO', 'FALHOU: insert indevido');
      DELETE FROM trecho_viagem WHERE id_viagem = 7 AND ordem = 99;
    END IF;
  END;

  -- T2: CHECK destino <> origem
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO viagem (id_usuario, id_local_origem, id_local_destino, inicio, status)
    VALUES (1, 1, 1, '2026-11-19 09:00:00', 'planejada');
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T2 CHECK destino <> origem', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T2 CHECK destino <> origem', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM viagem WHERE id_usuario = 1 AND id_local_origem = 1 AND id_local_destino = 1
        AND inicio = '2026-11-19 09:00:00';
    END IF;
  END;

  -- T3: CHECK nivel_congestionamento 0..5
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO leitura_trafego (id_sensor, registrado_em, velocidade_media_kmh, volume_veiculos, nivel_congestionamento)
    VALUES (1, '2026-11-18 15:00:00.000', 10.0, 100, 9);
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T3 CHECK nivel_congestionamento', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T3 CHECK nivel_congestionamento', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM leitura_trafego WHERE id_sensor = 1 AND registrado_em = '2026-11-18 15:00:00.000';
    END IF;
  END;

  -- T4: UNIQUE email
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO usuario (nome, email, ativo)
    VALUES ('Duplicado', 'ana.ficticia@exemplo.sp.br', TRUE);
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T4 UNIQUE email', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T4 UNIQUE email', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM usuario WHERE nome = 'Duplicado';
    END IF;
  END;

  -- T5: UNIQUE ref_unica (segundo carro referência)
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO modal_transporte (codigo, nome, categoria, sustentavel, referencia_comparacao)
    VALUES ('CARRO2', 'Outro carro ref', 'individual', FALSE, TRUE);
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T5 UNIQUE ref_unica (1 carro)', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T5 UNIQUE ref_unica (1 carro)', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM modal_transporte WHERE codigo = 'CARRO2';
    END IF;
  END;

  -- T6: Trigger sobreposição fator_emissao
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO fator_emissao (id_modal, id_fonte, g_co2_pkm, estimativa, vigencia_inicio, vigencia_fim)
    VALUES (4, 2, 85.000, FALSE, '2022-01-01', '2024-01-01');
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T6 Trigger sobreposição fator', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T6 Trigger sobreposição fator', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM fator_emissao WHERE id_modal = 4 AND g_co2_pkm = 85.000;
    END IF;
  END;

  -- T7: Trigger modal trecho ≠ modal linha
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO trecho_viagem (id_viagem, ordem, id_modal, id_linha, inicio, fim, distancia_km)
    VALUES (7, 50, 4, 1, '2026-11-19 08:00:00', '2026-11-19 08:30:00', 2.000);
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T7 Trigger modal≠linha no trecho', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T7 Trigger modal≠linha no trecho', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM trecho_viagem WHERE id_viagem = 7 AND ordem = 50;
    END IF;
  END;

  -- T8: Trigger sugestão de modal não sustentável (carro)
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO sugestao_modal (id_viagem, id_modal_sugerido, distancia_estimada_km, duracao_estimada_min, motivo)
    VALUES (7, 7, 5.000, 20, 'menor_co2');
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T8 Trigger sugestão sustentavel', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T8 Trigger sugestão sustentavel', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM sugestao_modal WHERE id_viagem = 7 AND id_modal_sugerido = 7;
    END IF;
  END;

  -- T9: FK inválida (sensor inexistente)
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO leitura_trafego (id_sensor, registrado_em, velocidade_media_kmh, volume_veiculos, nivel_congestionamento)
    VALUES (9999, '2026-11-18 16:00:00.000', 10.0, 10, 1);
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T9 FK leitura→sensor', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T9 FK leitura→sensor', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM leitura_trafego WHERE id_sensor = 9999;
    END IF;
  END;

  -- T10: Transação sp_registrar_viagem com trecho inválido → ROLLBACK
  BEGIN
    DECLARE v_id BIGINT UNSIGNED;
    DECLARE v_mensagem VARCHAR(255);
    DECLARE v_antes INT;
    DECLARE v_depois INT;
    SELECT COUNT(*) INTO v_antes FROM viagem WHERE id_usuario = 5 AND inicio = '2026-11-20 10:00:00';
    CALL sp_registrar_viagem(
      5, 1, 2,
      '2026-11-20 10:00:00', '2026-11-20 10:40:00', 'concluida',
      JSON_ARRAY(
        JSON_OBJECT(
          'ordem', 1,
          'id_modal', 4,
          'id_linha', 1,
          'inicio', '2026-11-20 10:00:00',
          'fim', '2026-11-20 10:40:00',
          'distancia_km', 4.5
        )
      ),
      v_id, v_mensagem
    );
    SELECT COUNT(*) INTO v_depois FROM viagem WHERE id_usuario = 5 AND inicio = '2026-11-20 10:00:00';
    IF v_id IS NULL AND v_depois = v_antes THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T10 ROLLBACK sp_registrar_viagem', 'ROLLBACK', 'ROLLBACK',
              LEFT(IFNULL(v_mensagem, 'sem viagem residual (rollback ok)'), 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T10 ROLLBACK sp_registrar_viagem', 'ROLLBACK', 'COMMIT',
              CONCAT('id=', IFNULL(v_id,'NULL'), ' msg=', IFNULL(v_mensagem,'')));
      IF v_id IS NOT NULL THEN
        DELETE FROM viagem WHERE id_viagem = v_id;
      END IF;
    END IF;
  END;

  -- T11: Transação válida (sucesso)
  BEGIN
    DECLARE v_id BIGINT UNSIGNED;
    DECLARE v_mensagem VARCHAR(255);
    CALL sp_registrar_viagem(
      5, 1, 2,
      '2026-11-20 11:00:00', '2026-11-20 11:40:00', 'concluida',
      JSON_ARRAY(
        JSON_OBJECT(
          'ordem', 1,
          'id_modal', 5,
          'id_linha', 1,
          'inicio', '2026-11-20 11:00:00',
          'fim', '2026-11-20 11:40:00',
          'distancia_km', 4.5
        )
      ),
      v_id, v_mensagem
    );
    IF v_id IS NOT NULL THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T11 sp_registrar_viagem sucesso', 'OK', 'OK',
              CONCAT('id_viagem=', v_id, ' ', IFNULL(v_mensagem,'')));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T11 sp_registrar_viagem sucesso', 'OK', 'FALHOU', LEFT(IFNULL(v_mensagem,''), 500));
    END IF;
  END;

  -- T12: CHECK estimativa exige fonte (período sem sobreposição na motocicleta)
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
      GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
      SET v_failed = 1;
    END;
    SET v_failed = 0; SET v_msg = NULL;
    INSERT INTO fator_emissao (id_modal, id_fonte, g_co2_pkm, estimativa, vigencia_inicio, vigencia_fim)
    VALUES (8, NULL, 100.000, FALSE, '2010-01-01', '2015-01-01');
    IF v_failed = 1 THEN
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T12 CHECK estimativa/fonte', 'REJEITADO', 'REJEITADO', LEFT(v_msg, 500));
    ELSE
      INSERT INTO tmp_resultado_teste(teste, esperado, obtido, detalhe)
      VALUES ('T12 CHECK estimativa/fonte', 'REJEITADO', 'ACEITO', 'FALHOU');
      DELETE FROM fator_emissao WHERE id_modal = 8 AND g_co2_pkm = 100.000 AND vigencia_inicio = '2010-01-01';
    END IF;
  END;

  SELECT * FROM tmp_resultado_teste ORDER BY id;

  SELECT
    SUM(esperado = obtido) AS testes_ok,
    SUM(esperado <> obtido) AS testes_falhos,
    COUNT(*) AS total
  FROM tmp_resultado_teste;
END$$

DELIMITER ;

CALL sp_rodar_testes();

-- ### FIM: 08_testes.sql ###

