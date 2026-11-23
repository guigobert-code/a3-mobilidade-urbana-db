# Enunciado – Projeto A3 – Banco de Dados (cópia em texto)

Fonte: https://docs.google.com/document/d/e/2PACX-1vTYQGrb5k61Mb0ihf3wIWC59WZ_zET6DM_lOrLU3qKnK2r-TbsHl_l1RciNcQ3XUWa5bsiv-o0NyF1B/pub
Capturado em 18/11/2026 (documento publicado "atualizado automaticamente a cada 5 minutos").
Observações da captura:
- As únicas imagens do documento são os logotipos "Universidade Anhembi Morumbi" e "Ânima Educação".
- A seção 3 (ESTRUTURA DO RELATÓRIO FINAL) contém apenas a frase sobre o formato PDF; a lista de seções do relatório NÃO aparece no documento publicado.
- Não há datas, prazos, tamanho de grupo, tempo de apresentação nem template no documento.

---

Projeto A3- Publicada usando o Google Docs
Denunciar abusoSaiba mais

Projeto A3
Atualizado automaticamente a cada 5 minutos

Projeto A3 – BANCO DE DADOS 

Soluções em Banco de Dados aplicados à Sustentabilidade 
1. CONTEXTUALIZAÇÃO DO PROJETO 
1.1. O Conceito de Sustentabilidade e Banco de Dados no Projeto 
A sustentabilidade tornou-se uma prioridade global, abrangendo dimensões ambientais,  sociais e econômicas. Paralelamente, a gestão eficiente de dados é o alicerce para  qualquer solução tecnológica que vise monitorar, otimizar e transformar processos  sustentáveis. 
Neste projeto, os estudantes deverão atuar como consultores de dados e inovação,  propondo uma solução baseada em banco de dados que: 
• Enderece um problema real de sustentabilidade (ambiental, social ou econômica); 
• Utilize conceitos avançados de modelagem, SQL, normalização, integridade  referencial, transações, segurança e administração de dados; 
• Crie impacto positivo mensurável na comunidade, no meio ambiente ou na  economia. 
Busque uma solução que vá além da simples automação. Deve transformar a forma como o  problema é abordado, gerando novos modelos de operação, engajamento e impacto, com  foco na qualidade, consistência e segurança dos dados. 
1.2. Opções de Escopo - Projetos de Sustentabilidade com Banco de Dados

Projeto 
Problema Atual 
Oportunidade com Banco de  Dados

Smart  
Reciclagem
Descarte incorreto de  
resíduos; baixa adesão à  coleta seletiva; contaminação  de materiais recicláveis.
Sistema com BD relacional  para rastrear resíduos,  
armazenar histórico de  
usuários, calcular métricas de  reciclagem e gerar relatórios  para cooperativas.

BD para  
Agricultura  
Sustentável
Uso excessivo de água e  
defensivos; perda de safras  por pragas ou clima; baixa  produtividade.
Banco de dados geoespacial  para armazenar dados de  sensores, previsões  
climáticas, histórico de safras  e recomendações de manejo  por talhão.

Gestão  
Inteligente de  
Energia
Desperdício de energia em  residências/comércios; falta  de conscientização sobre  consumo; pico de demanda  desnecessário.
BD com séries temporais para  armazenar consumo em  
tempo real, prever padrões,  gerar alertas e integrar dados  de fontes renováveis.

Redução de  
Desperdício  
Alimentar
Restaurantes, supermercados  e residências descartam  grandes quantidades de  
alimentos; produção  
desalinhada com a demanda.
Plataforma com BD para  
conectar excedentes a  
instituições, prever demanda,  armazenar receitas e gerar  métricas de redução de  
desperdício.

Mobilidade  
Urbana  
Sustentável
Trânsito intenso, emissão de  poluentes, uso ineficiente do  transporte público e rotas não  otimizadas.
BD com dados de tráfego em  tempo real, histórico de  
deslocamentos, sugestão de  modais sustentáveis e cálculo  de emissões de CO₂.

Monitoramento  de  
Desmatamento  e Queimadas
Dificuldade de monitorar  áreas remotas; detecção  tardia de  
desmatamento/queimadas;  ações de fiscalização  
ineficientes.
BD geoespacial com imagens  de satélite, alertas, histórico  de focos de calor e integração  com órgãos ambientais.

Educação  
Ambiental  
Gamificada
Baixo engajamento em temas  de sustentabilidade; falta de  conscientização sobre  
impacto ambiental diário.
BD relacional para armazenar  perfil de usuários, progresso,  conquistas, hábitos e pegada  de carbono calculada.

Otimização de  Rotas de Coleta  de Lixo
Coleta de lixo ineficiente,  consumo elevado de  
combustível, tempo de  
deslocamento elevado, coleta  desbalanceada.
BD com dados de sensores de  nível dos contêineres,  
histórico de rotas e otimização  dinâmica de percursos.

BD para  
Qualidade do Ar  e Água
Poluição do ar e da água sem  monitoramento contínuo e  acessível; falta de dados para  políticas públicas.
Rede de sensores + BD  
relacional/geoespacial para  armazenar medições, prever  qualidade e emitir alertas à  população.

Supply Chain  
Verde
Cadeias de suprimento com  alta emissão de carbono; falta  de rastreabilidade de origem  sustentável; dificuldade de  certificação.
BD com rastreabilidade,  
pegada de carbono por etapa,  recomendação de  
fornecedores sustentáveis e  relatórios para certificação.

Energy  
Harvesting e  
Consumo  
Inteligente
Dispositivos IoT com baterias  que acabam rapidamente;  manutenção frequente em  áreas remotas.
BD para armazenar predições  de consumo, histórico de  energia coletada e otimização  de uso de baterias.

Economia  
Circular de  
Resíduos  
Eletrônicos
Descarte incorreto de  
eletrônicos (lixo eletrônico);  falta de logística reversa;  perda de materiais valiosos.
BD para rastrear  
componentes, destinos  
corretos, logística reversa e  conectar recicladores a  
geradores de resíduos.

Turismo  
Sustentável
Turismo com grande impacto  ambiental; falta de informação  sobre práticas sustentáveis;  superlotação de destinos.
BD com dados de destinos,  hospedagens ecológicas,  pegada de carbono por viagem  e recomendações  
personalizadas.

Gestão  
Inteligente de  
Água
Perda de água em  
distribuição; consumo  
excessivo; falta de informação  em tempo real; vazamentos  não detectados.
BD com dados de sensores,  histórico de consumo,  
detecção de vazamentos e  recomendações de redução.

Gestão de  
Resíduos  
Hospitalares
Hospitais geram grande  
volume de resíduos perigosos;  rastreabilidade ineficiente;  riscos à saúde e ao meio  ambiente.
BD para rastrear resíduos  desde a origem até o descarte  final, com controle de  
validade, categorização por  periculosidade e relatórios  para órgãos fiscalizadores.

Rastreabilidade  de Produtos  
Orgânicos e  
Agroecológicos
Produtores orgânicos  
enfrentam dificuldade de  comprovar origem e práticas  sustentáveis; consumidores  não confiam na certificação.
BD com rastreabilidade  
completa da cadeia produtiva,  armazenando certificações,  práticas agrícolas e histórico  de produção, com acesso via  QR Code.

Gestão de  
Biodiversidade e  Espécies  
Ameaçadas
Dados sobre espécies  
ameaçadas são  
fragmentados; falta de  
integração entre  
pesquisadores e órgãos  
ambientais.
BD colaborativo para  
armazenar avistamentos,  monitoramento populacional,  áreas de preservação e alertas  de risco, integrando dados de  múltiplas fontes.

BD para  
Energias  
Renováveis  
Distribuídas  
(Usinas Solares  e Eólicas)
Operadores de usinas  
renováveis têm dificuldade de  integrar dados de geração,  clima, manutenção e  
demanda.
BD com séries temporais para  armazenar dados de geração,  previsão climática, histórico  de manutenção e otimização  de produção por ativo.

Mapeamento de  Áreas de Risco  Climático
Desastres climáticos  
(enchentes, deslizamentos)  causam perdas humanas e  materiais; falta de dados  preditivos.
BD geoespacial com dados  históricos de eventos  
climáticos, vulnerabilidade de  áreas, alertas em tempo real e  integração com defesa civil.

2. ENTREGÁVEIS 

Entregável 
Descrição

Modelagem Conceitual e  Lógica
Diagrama Entidade-Relacionamento (DER) completo,  com identificação de entidades, atributos,  relacionamentos, chaves primárias e estrangeiras.  Aplicação de normalização (até 3ª FN).

Repositório Github 
Código SQL contendo: criação do banco de dados,  criação de tabelas, constraints, índices, views,  triggers, stored procedures (quando aplicável),  consultas para relatórios e dados de teste.

3. ESTRUTURA DO RELATÓRIO FINAL (PDF) - OBRIGATÓRIO 

Entregar um arquivo no formato PDF. Não serão aceitos relatórios  em qualquer outro tipo de formato. 

4. ORIENTAÇÕES PARA A APRESENTAÇÃO ORAL 

Parte 
Foco

1. Diagnóstico e  
problema
Como o cenário atual (sustentabilidade) funciona hoje?  Quais as principais dores e ineficiências relacionadas a  dados?

2. Visão de  
transformação com  
Banco de Dados
Como será diferente com uma gestão eficiente de dados?  Que valor sustentável entrega (ambiental, social,  econômico)?

3. Modelagem e  
Requisitos
O que a solução fará para viabilizar a transformação  sustentável? Como os dados serão modelados e  armazenados?

4. Arquitetura, Segurança  e Viabilidade
É viável tecnicamente e financeiramente? Como será  construída? Como serão garantidos segurança, integridade  e recuperação?

5. Considerações finais 
Aprendizados, desafios, impacto mensurável, próximos  passos.

O que será avaliado na apresentação 

✓ Clareza ao comunicar a proposta sustentável com banco de dados 
✓ Demonstração convincente da aplicação dos conceitos de BD (modelagem, SQL,  normalização, segurança) 
✓ Domínio do conteúdo por toda a equipe
✓ Capacidade de responder perguntas sobre a solução e o impacto 
✓ Cumprimento do tempo 

5. CRITÉRIOS DE AVALIAÇÃO

Critério 
Descrição

Clareza das  
informações  
apresentadas
Relatório e apresentação organizados, linguagem adequada e  objetiva.

Criatividade na  
proposta de soluções
Originalidade e adequação da solução ao problema da sustentabilidade, com uso inovador de conceitos de banco de  dados.

Qualidade da  
Modelagem de Dados
DER completo, normalização correta, integridade referencial,  uso adequado de chaves e constraints.

Qualidade e  
organização do  
relatório
Estrutura completa, profundidade da análise, coerência entre  as seções.

Domínio dos conteúdos  discutidos
Segurança na apresentação, argumentação consistente e  capacidade técnica de explicar o projeto de BD.

Viabilidade da solução 
A solução é tecnicamente viável? O uso do SGBD é adequado  e justificado? O impacto sustentável é mensurável?

Segurança e  
Administração de  
Dados
Plano de acesso, backup, recuperação e monitoramento bem  definidos.

Atenção: 

- A avaliação da apresentação será individual, ou seja, os professores irão endereçar perguntas para cada um dos integrantes com diferenciação de notas.

- O desempenho na avaliação oral terá impacto significativo na nota caso o aluno não consiga explicar os questionamentos indicando falta de envolvimento e participação no desenvolvimento do trabalho.