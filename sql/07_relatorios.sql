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
