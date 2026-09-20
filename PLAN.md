# Plano de porte do SICAR de Python para R

## Decisão

O porte é **tecnicamente viável** como um pacote R nativo. A maior parte da
implementação Python é pequena e corresponde diretamente a recursos maduros do
ecossistema R: requisições com cookies, parsing de HTML, download em arquivo,
validação de argumentos, progresso, retentativas e OCR com Tesseract.

O risco global é **médio**, não por causa da linguagem, mas por duas dependências
externas:

1. o fluxo HTTP do SICAR é peculiar e pode mudar sem aviso;
2. a taxa de acerto do CAPTCHA depende fortemente do pré-processamento da imagem.

O desenvolvimento deve começar por uma prova de conceito curta para esses dois
pontos. Se os gates dessa prova forem atingidos, não há impedimento conhecido para
entregar o pacote.

## Evidências da avaliação

### Escopo da referência

A versão Python em `ref/SICAR` tem aproximadamente 900 linhas de código de
produção, incluindo muita documentação inline. Seu comportamento essencial é:

- iniciar uma sessão e preservar cookies;
- obter e interpretar as datas de disponibilização por UF;
- baixar um CAPTCHA PNG e resolvê-lo por um driver;
- baixar um ZIP para uma combinação de UF e tema;
- repetir o fluxo quando o CAPTCHA ou o download falhar;
- executar a mesma operação para as 27 UFs.

Os nove temas e as 27 UFs são dados estáticos simples. O driver Tesseract pode ser
portado com os pacotes R `tesseract` e `magick`. O driver PaddleOCR é opcional na
referência e não precisa bloquear a primeira versão.

### Verificação ao vivo em 20/09/2026

Uma verificação somente de leitura nos endpoints oficiais mostrou que:

- a primeira chamada HTTPS devolve `302` para uma URL HTTP;
- seguir automaticamente esse redirecionamento causa um ciclo HTTP/HTTPS;
- a resposta `302` inicial, apesar de vazia, define os cookies necessários;
- reutilizando esses cookies e chamando diretamente HTTPS, a página de datas
  devolveu `200 text/html`, cerca de 40 kB e registros para as 27 UFs;
- no mesmo contexto, o endpoint de CAPTCHA devolveu `200 image/png`.

Isso confirma que o fluxo ainda pode ser implementado, mas também mostra por que
o cliente deve modelar explicitamente a inicialização da sessão. Um `302` não
deve ser tratado genericamente como sucesso: ele é aceitável apenas no bootstrap.

O Tesseract chamado diretamente pelo R, sem pré-processamento, reconheceu
corretamente apenas 1 dos 6 PNGs de teste existentes. Isso não mede o resultado do
porte completo, pois a referência aplica limiarização e operações morfológicas
antes do OCR. O resultado justifica um gate específico para reproduzir e medir esse
pipeline antes de tornar o OCR automático o comportamento padrão.

### Problemas da referência que não devem ser copiados

- `chunk_size` faz parte da API Python, mas não é usado pelo iterador de download.
- O download nacional cria um subdiretório para cada UF, mas salva os ZIPs no
  diretório raiz.
- Falha após todas as tentativas retorna `None`, sem dar ao chamador a causa final.
- A validação se limita a status, tamanho e `Content-Type`; o ZIP pode ser validado
  antes de substituir o arquivo de destino.
- A API orientada a classes e enums é natural em Python, mas não é a interface mais
  idiomática para usuários de R.

## Escopo da primeira versão

### Incluído

- cliente persistente com cookies e TLS verificado;
- consulta das datas de disponibilização;
- download por UF e tema;
- download nacional sequencial;
- solucionador Tesseract, desde que passe o gate de acurácia;
- solucionador manual e interface para solucionadores definidos pelo usuário;
- retentativas, backoff com jitter, progresso e erros estruturados;
- documentação, testes unitários, testes de contrato opcionais e CI;
- compatibilidade com Linux, macOS e Windows.

### Fora do escopo inicial

- reimplementar PaddleOCR em R;
- ler, unir ou transformar os shapefiles baixados;
- downloads paralelos por padrão;
- contornar mudanças de CAPTCHA ou controles de acesso do serviço;
- garantir estabilidade de um serviço externo que não oferece API versionada.

PaddleOCR pode ser acrescentado depois por um adaptador opcional via `reticulate`,
sem tornar Python uma dependência do núcleo do pacote.

## API R proposta

Usar uma interface funcional sobre um objeto S3 que guarda a configuração e o
arquivo temporário de cookies:

```r
client <- sicar_client(solver = sicar_solver_tesseract())

sicar_release_dates(client)
sicar_download_state(
  client,
  state = "PA",
  polygon = "APPS",
  dest_dir = "SICAR/PA"
)
sicar_download_country(
  client,
  polygon = "RESERVA_LEGAL",
  dest_dir = "SICAR"
)
```

Superfície pública inicial:

- `sicar_client(solver, headers, timeout)`: cria o cliente, mas adia acesso à rede
  até a primeira operação;
- `sicar_release_dates(client)`: retorna um `data.frame` com `state` e `date`, sendo
  `date` da classe `Date`;
- `sicar_download_state(client, state, polygon, dest_dir, overwrite, tries)`:
  retorna o caminho normalizado do ZIP;
- `sicar_download_country(client, polygon, dest_dir, overwrite, tries)`:
  retorna um `data.frame` com uma linha por UF, caminho e status;
- `sicar_states()` e `sicar_polygon_types()`: expõem os valores aceitos;
- `sicar_solver_tesseract()`, `sicar_solver_manual()` e
  `sicar_solver_function(fn)`: implementam uma interface comum de CAPTCHA.

Decisões de comportamento:

- aceitar UF e tema sem diferenciar maiúsculas de minúsculas, mas sempre
  normalizar para os valores oficiais;
- emitir erros com classes `rscicar_*`, mensagens em inglês para consistência com
  pacotes R e campos com contexto (`url`, `state`, `polygon`, `attempt`);
- falhar explicitamente depois de esgotar as tentativas no download de uma UF;
- no download nacional, continuar nas demais UFs e devolver falhas por linha,
  emitindo ao final um aviso resumido;
- não sobrescrever arquivos por padrão;
- baixar para um arquivo temporário no diretório de destino, validar o ZIP e só
  então fazer a renomeação atômica;
- manter execução sequencial por respeito ao serviço e para preservar a sessão.

## Arquitetura e dependências

### Dependências principais

- `httr2`: montagem das requisições, download direto para arquivo, progresso,
  timeouts e política de erros;
- `xml2` ou `rvest`: parsing da página de datas;
- `cli`: mensagens, erros e avisos estruturados;
- `rlang`: classes de condição e validação, se `cli` não for suficiente.

### Dependências opcionais

- `tesseract` e `magick`: OCR e pré-processamento; devem ficar em `Suggests` para
  que o pacote possa ser instalado sem bibliotecas de sistema;
- `testthat`, `webfakes` e `withr`: testes;
- `progressr`: somente se o progresso do `httr2` não cobrir bem operações com
  várias UFs.

O pacote deve verificar as dependências opcionais no momento de construir o
solucionador e fornecer instrução clara de instalação. A alternativa manual ou uma
função fornecida pelo usuário deve funcionar sem OCR local.

### Sessão HTTP

O cliente deve encapsular:

- URLs oficiais em um único arquivo interno;
- cookie jar exclusivo por cliente, removido pelo finalizador da sessão R;
- cabeçalhos padrão e possibilidade de extensão pelo usuário;
- bootstrap HTTPS sem seguir o `302`, preservando os cookies recebidos;
- chamadas posteriores diretamente por HTTPS;
- TLS 1.2 quando necessário para compatibilidade, sempre mantendo validação de
  certificado e hostname;
- validação específica de status e tipo de conteúdo para HTML, PNG e ZIP;
- timeout de conexão e timeout de baixa velocidade adequados a arquivos grandes.

Não desativar validação TLS. Como as opções de TLS do `libcurl` variam por
plataforma, o spike deve testar explicitamente os backends usados por Linux, macOS
e Windows.

### Estrutura prevista

```text
DESCRIPTION
LICENSE
LICENSE.md
NAMESPACE
NEWS.md
R/
  client.R
  conditions.R
  constants.R
  download.R
  http.R
  release-dates.R
  solver.R
  solver-manual.R
  solver-tesseract.R
  validate.R
tests/testthat/
  fixtures/
  helper-fixtures.R
  test-client.R
  test-download.R
  test-http.R
  test-release-dates.R
  test-solver-tesseract.R
  test-validate.R
vignettes/
  getting-started.Rmd
  captcha-solvers.Rmd
```

## Plano de execução

### Fase 0 — congelar o contrato e a proveniência

1. Registrar a versão/commit exato de `ref/SICAR` usado como referência.
2. Extrair uma matriz de comportamento a partir da API e dos testes Python.
3. Documentar divergências intencionais da API R, inclusive tratamento de falhas e
   organização dos arquivos por UF.
4. Adotar licença MIT e preservar o aviso de copyright do projeto original em um
   arquivo de atribuição, pois o novo código será derivado dele.

**Saída:** contrato de compatibilidade revisável e metadados de licença.

### Fase 1 — spike dos riscos externos

1. Implementar uma sessão mínima com cookie jar.
2. Confirmar o bootstrap `302`, a consulta de datas `200` e o CAPTCHA `200` sem
   desativar TLS.
3. Reproduzir em R o pipeline da referência: conversão para escala de cinza,
   limiarização de Otsu, dilatações e erosões, Tesseract com `psm 7` e whitelist
   alfanumérica.
4. Comparar o resultado com os PNGs versionados e registrar acurácia, tempo e
   diferenças entre sistemas operacionais.
5. Fazer um download real pequeno, com limite de tentativas e sem o incluir na CI.

**Gates para continuar:**

- datas de todas as 27 UFs interpretadas corretamente;
- CAPTCHA obtido mantendo a mesma sessão;
- os 3 fixtures usados pelos testes Tesseract da referência reconhecidos em 3/3;
- pelo menos um ZIP real baixado, identificado como ZIP e aberto por `unzip`;
- nenhuma necessidade de desativar verificação de certificado.

Se o gate de OCR falhar, o pacote continua viável, mas o solucionador manual passa
a ser o padrão e o Tesseract fica experimental até atingir o critério.

### Fase 2 — esqueleto do pacote e domínio

1. Criar o pacote com `usethis`, `roxygen2` e testthat edition 3.
2. Configurar `DESCRIPTION`, licença, `NAMESPACE`, `NEWS.md`, README e CI.
3. Implementar tabelas de UFs e temas, normalização e validação.
4. Criar classes de erro e o objeto S3 `sicar_client` sem efeitos de rede no
   construtor.
5. Documentar todas as funções exportadas e exemplos que não acessem a rede no
   `R CMD check`.

**Saída:** pacote instalável com API pública definida e testes de domínio.

### Fase 3 — camada HTTP e datas

1. Implementar bootstrap, cookies, TLS, cabeçalhos e timeouts.
2. Implementar validadores distintos para HTML, PNG e ZIP.
3. Implementar `sicar_release_dates()` com seletores tolerantes a elementos
   ausentes, validação de 27 UFs e conversão explícita de `%d/%m/%Y`.
4. Guardar uma fixture HTML sanitizada e testar mudanças parciais no markup.
5. Criar testes locais com `webfakes` para cookies, redirecionamento, status,
   `Content-Type`, timeout e respostas truncadas.

**Saída:** consulta de datas coberta por testes e sem rede obrigatória na suíte.

### Fase 4 — solucionadores de CAPTCHA

1. Definir o contrato `function(path) -> string` e exigir exatamente cinco
   caracteres alfanuméricos após normalização.
2. Implementar um adaptador para funções do usuário, facilitando testes e futuros
   drivers.
3. Implementar o solucionador manual para sessões interativas, com erro claro em
   execução não interativa.
4. Implementar o pré-processamento Tesseract validado no spike.
5. Testar ausência das dependências opcionais, texto vazio, caracteres inválidos e
   os fixtures conhecidos.

**Saída:** CAPTCHA desacoplado da rede e extensível sem alterar o núcleo.

### Fase 5 — downloads

1. Implementar download por UF com URL codificada, arquivo temporário no destino,
   progresso e timeouts.
2. Validar status `200`, `Content-Type` compatível, tamanho não zero, assinatura
   `PK` e integridade via `unzip(list = TRUE)`.
3. Implementar retentativas somente para falhas transitórias e CAPTCHA rejeitado;
   não repetir erros de validação do usuário ou de permissão local.
4. Aplicar backoff limitado com jitter e permitir injetar espera/aleatoriedade nos
   testes.
5. Implementar download nacional em `dest_dir/<UF>/<UF>_<TEMA>.zip`, sequencial,
   com resultado tabular e retomada baseada nos ZIPs já validados.
6. Garantir limpeza de arquivos parciais em erro ou interrupção.

**Saída:** paridade funcional de download, com semântica de falha e arquivos mais
seguros que na referência.

### Fase 6 — documentação, portabilidade e release

1. Escrever README em português com instalação, requisitos de sistema e exemplos.
2. Criar vignettes de introdução e de solucionadores de CAPTCHA.
3. Configurar CI para versões release/devel de R em Linux, macOS e Windows.
4. Rodar `air format .`, `devtools::document()`, `devtools::test()`,
   `pkgdown::check_pkgdown()` quando aplicável e `devtools::check()`.
5. Rodar testes ao vivo somente em job agendado/manual, com baixo volume, nunca no
   check normal nem no CRAN.
6. Publicar primeiro uma versão de desenvolvimento e observar o contrato externo
   antes de preparar CRAN.

**Saída:** pacote documentado, verificável e pronto para uso controlado.

## Estratégia de testes

### Unitários e de componente

- validação completa das 27 UFs e dos 9 temas;
- parsing de datas, campos ausentes, duplicatas e datas inválidas;
- construção e codificação das URLs;
- classes e metadados dos erros;
- normalização da saída dos solucionadores;
- política de retentativas e backoff sem espera real;
- nomes, destinos, `overwrite` e limpeza de arquivos parciais;
- validação de ZIP bom, HTML disfarçado de sucesso, arquivo vazio e ZIP truncado.

### Servidor HTTP local

Usar `webfakes` para simular o protocolo completo:

1. bootstrap responde `302` e define cookie;
2. CAPTCHA e download recusam requisições sem o cookie;
3. primeiras tentativas devolvem CAPTCHA inválido ou HTML;
4. tentativa final entrega um ZIP fixture em partes;
5. o teste confirma cookies, retentativas, progresso, integridade e caminho final.

### Contrato ao vivo

Testes protegidos por `RSCICAR_RUN_LIVE_TESTS=true` devem verificar apenas:

- disponibilidade dos endpoints;
- 27 datas parseáveis;
- MIME do CAPTCHA;
- um download de tamanho controlado, executado manualmente ou em baixa frequência.

Falhas ao vivo devem indicar possível mudança de contrato, sem tornar a suíte
offline instável.

## Critérios de aceite da primeira versão

- `R CMD check` sem erros, avisos ou notas causadas pelo pacote nas plataformas de
  CI suportadas;
- cobertura unitária de pelo menos 90% das linhas do núcleo, sem contar integração
  ao vivo;
- consulta ao vivo retorna exatamente as 27 UFs e datas válidas;
- um download real por UF produz ZIP íntegro e reutilizável;
- interrupções e falhas não deixam o arquivo final corrompido;
- download nacional respeita subdiretórios, preserva sucessos e relata falhas;
- OCR automático só é padrão se passar 3/3 fixtures Tesseract da referência em
  todas as plataformas suportadas;
- instalação e uso sem Tesseract continuam possíveis por solver manual/customizado;
- licença e atribuição da implementação original estão preservadas.

## Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---:|---|
| Mudança de HTML ou endpoint | Alto | URLs centralizadas, fixtures, parser defensivo e teste de contrato agendado |
| Ciclo de redirecionamento | Alto | Bootstrap sem `follow`, cookie jar explícito e teste local do fluxo |
| Baixa acurácia do OCR | Alto | Gate de fixtures, retentativas, solver manual e interface customizada |
| Diferenças de TLS/libcurl | Alto | Matriz de CI e proibição de desativar verificação TLS |
| Arquivos estaduais muito grandes | Médio | Streaming para disco, progresso, timeouts e validação antes do rename |
| Sobrecarga no serviço | Médio | Sequencial por padrão, jitter, retomada e testes ao vivo parcimoniosos |
| Dependências de sistema do OCR | Médio | `Suggests`, diagnóstico claro e solver manual/customizado |
| CAPTCHA alterado ou mecanismo anti-bot | Alto | Isolar solver; não prometer contorno; reavaliar compatibilidade |

## Estimativa

Para uma pessoa familiarizada com desenvolvimento de pacotes R:

- spike e contrato: 2–3 dias;
- pacote, HTTP, parsing e testes locais: 4–6 dias;
- OCR e downloads robustos: 4–7 dias;
- documentação, CI e ajustes multiplataforma: 3–5 dias.

Estimativa total: **13–21 dias úteis**, com a maior variação no OCR e na
compatibilidade TLS entre plataformas. Um MVP com solver manual/customizado e sem
download nacional pode ser entregue antes, em aproximadamente **7–10 dias úteis**.

## Recomendação final

Prosseguir com o porte, iniciando pela Fase 1. A arquitetura deve ser nativa em R e
desacoplar o CAPTCHA desde o primeiro commit. Não há vantagem em envolver a
implementação Python via `reticulate` no núcleo: isso manteria as dependências mais
pesadas do projeto original e reduziria a portabilidade sem resolver a fragilidade
do serviço externo.
