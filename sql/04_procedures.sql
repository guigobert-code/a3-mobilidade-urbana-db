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
