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
