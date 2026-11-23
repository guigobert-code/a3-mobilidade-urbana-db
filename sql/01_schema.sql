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
