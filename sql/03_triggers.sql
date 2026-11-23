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
