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
