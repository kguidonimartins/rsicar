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
- recortar ou transformar permanentemente os shapefiles baixados; a seleção
  municipal por interseção é oferecida por `sicar_extract_municipality()`;
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
- `sicar_resolve_municipality(x, uf, strict)`: resolve nomes, códigos IBGE,
  UFs e identificadores `Municipio/UF` usando a malha municipal de 2025
  integrada ao pacote;
- `sicar_extract_municipality(x, src_dir)`: lê um ZIP ou todos os ZIPs de uma
  pasta, seleciona com `sf::st_intersects()` as feições SICAR que tocam os
  municípios solicitados e retorna um objeto `sf` sem gravar arquivos.

Decisões de comportamento:

- aceitar UF e tema sem diferenciar maiúsculas de minúsculas, mas sempre
  normalizar para os valores oficiais;
- emitir erros com classes `rsicar_*`, mensagens em inglês para consistência com
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

Testes protegidos por `RSICAR_RUN_LIVE_TESTS=true` devem verificar apenas:

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

## Auditoria do estado atual (2026-09-21)

Auditoria do repositório com teste de download real (Sergipe, `AREA_IMOVEL`,
`tries = 5`), CAPTCHA resolvido por leitura visual dos PNGs (equivalente ao
solver manual) e uma execução controlada do `sicar_solver_tesseract()` contra
os 6 fixtures de CAPTCHA da referência Python.

### Teste de download — Sergipe

`sicar_download_state(client, "se", "AREA_IMOVEL", ..., tries = 5)` contra o
serviço real:

```
[attempt 1] CAPTCHA correto "inRvK"  -> enviado como INRVK -> 200 application/json (rejeitado)
[attempt 2..5] CAPTCHAs novos        -> rejeitados
RESULT: FAILED — "Download failed on attempt 5."
```

As 5 tentativas falharam, apesar de a tentativa 1 ter lido o CAPTCHA
corretamente. Repetindo com uma única linha corrigida (ver bloqueador 1):

```
RESULT: SUCCESS
path: SE_AREA_IMOVEL.zip
size: 38.323.401 bytes | 5 entradas (.shp .dbf .shx .prj .fix)
```

### Bloqueador 1 — `toupper()` inutiliza todo download

`R/solver.R` normaliza a saída do solver com `toupper(trimws(value))`. Os
CAPTCHAs do SICAR são **case-sensitive**. Evidência ao vivo:

| enviado | CAPTCHA real | resposta |
|---|---|---|
| `WfDKS` | `WfDKS` | `200 application/zip`, 38,3 MB |
| `AVGKD` | `AVGKd` | `200 application/json` — "Os caracteres da imagem não foram digitados corretamente." |
| `INRVK` | `inRvK` | `200 application/json` (idem) |

A referência Python (`sicar.py`, `download_state`) nunca altera a caixa do
CAPTCHA, só confere `len(captcha) == 5`. Correção: remover o `toupper()` do
solver e ajustar o regex para `^[A-Za-z0-9]{5}$`. O `toupper()` aplicado a UF
e tema em `R/validate.R` está correto e deve permanecer — a normalização
case-insensitive nesse caso é intencional (ver seção "Decisões de
comportamento").

### Bloqueador 2 — solver Tesseract com 0% de acerto

Resultado nos 6 fixtures da referência (o gate da Fase 1 exige 3/3):

```
AbgBy -> Abok    Ca7Qk -> era     n3aoD -> ASROU
qMT5V -> GFN     sgffr -> Syftr   ZS7pc -> Lott     => 0/6
```

Também 0/6 em CAPTCHAs reais obtidos ao vivo — nenhuma tentativa produziu
sequer 5 caracteres válidos. Foi testada a hipótese de que faltava achatar o
canal alfa (PNGs são gray+alpha e `.sicar_tesseract_preprocess()` não faz o
flatten que a referência faz via `imsave`); adicionar
`image_flatten(image_background(img, "white"))` muda a saída mas o resultado
continua **0/6**. A divergência do pipeline de pré-processamento é maior:
`cv2.threshold(..., THRESH_TRUNC | THRESH_OTSU)` virou
`magick::image_threshold(type = "black")`, e as operações morfológicas do
OpenCV rodam sobre a imagem binarizada, não sobre grayscale, na referência.
Combinado ao bloqueador 1, nenhum download não interativo funciona hoje com o
solver Tesseract.

### Achados adicionais (severidade "major")

- **`302` classificado como não retentável.** `.sicar_require_response()`
  trata qualquer status fora do esperado, incluindo `302`, como erro fatal
  não retentável. Verificado ao vivo: com `tries = 5`, uma sessão expirada
  consome só 1 tentativa antes de abortar. Além disso, `.sicar_bootstrap()`
  nunca reexecuta depois de `bootstrapped = TRUE`, então o cliente não se
  recupera sozinho de uma sessão perdida.
- **`timeout` é o tempo total da requisição**, com padrão de 60 s, mapeado
  para a opção `timeout` do curl. SE tem 38 MB; outros estados chegam a
  centenas de MB. Isso contradiz a diretriz da Fase 1 de usar "timeout de
  conexão e timeout de baixa velocidade adequados a arquivos grandes" — a
  opção correta é `connecttimeout` combinada com `low_speed_limit` /
  `low_speed_time`.
- **Os testes offline nunca exercitam a forma real de falha do CAPTCHA
  rejeitado.** Os mocks simulam HTML ou não-ZIP; ao vivo a rejeição é
  `200 application/json` de 58 bytes ("caracteres... não foram digitados
  corretamente"). `test-live.R` cobre apenas `sicar_release_dates()` — o gate
  de aceitação da Fase 1 ("pelo menos um ZIP real baixado, identificado como
  ZIP e aberto por `unzip`") não constava dos testes automatizados; se
  constasse, o bloqueador 1 teria sido pego antes.

### Achados menores

- `runif` usado sem `importFrom("stats", "runif")` → NOTE do
  `R CMD check`; `utils::`/`stats::` não declarados em `Imports`.
- Falta `Depends: R (>= 4.1)`: o pipe nativo `|>` e a vetorização de
  `utils::URLencode()` exigem R ≥ 4.1.0.
- `LICENSE` tem o texto MIT completo, mas `License: MIT + file LICENSE`
  espera o stub DCF de duas linhas → NOTE "License stub is invalid DCF".
  `LICENSE.md` foi usado para a atribuição ao projeto upstream em vez do
  texto de licença renderizado.
- `NEWS.md` → NOTE "No news entries found" (falta cabeçalho de versão no
  formato que `R CMD check` reconhece).
- Nenhuma função exportada tem `@examples` executável, apesar de o AGENTS.md
  pedir "um exemplo quando fizer sentido" (`checking examples ... NONE`).
- Os parâmetros de injeção de dependência (`wait`, `random`,
  `attempt_download`, `download_state`) são argumentos públicos e
  documentados de `sicar_download_state()`/`sicar_download_country()`, o que
  expõe detalhes internos de teste na API pública.
- Código morto: o bloco final de erro em `sicar_download_state()` (depois do
  loop `for`) é inalcançável; em `.sicar_download_zip()`, o `writeBin()`
  condicional também é inalcançável porque `req_perform(path =)` já grava o
  arquivo.
- `sicar_download_country()` não valida `client` nem `dest_dir` antes de
  iterar, ao contrário de `sicar_download_state()`.
- Estilo de mock HTTP inconsistente entre arquivos de teste
  (`withr::local_options(httr2_mock = ...)` em um teste de `test-http.R`
  versus `httr2::local_mocked_responses()` no restante da suíte).
- `out-check.txt` e `out-testthat.txt` commitados estão desatualizados
  (mostram 16 testes; a suíte atual tem 48).
- `webfakes`, mencionado na Fase 3 como ferramenta de simulação de
  protocolo, não está em `Suggests` nem em uso.

### O que está correto

TLS nunca é enfraquecido — a referência Python precisa fixar TLS 1.2 e uma
lista específica de cifras para compatibilidade com o servidor SICAR; o porte
R não precisou desse contorno. O pipeline de download (stream para arquivo
temporário dentro de `dest_dir`, checagem de assinatura `PK`, validação via
`unzip(list = TRUE)` e rename somente após validar) funcionou de ponta a
ponta em um arquivo real de 38 MB. As condições estruturadas `rsicar_*`
carregam campos de contexto úteis. `air format --check .` está limpo, os 48
testes offline passam e `R CMD check` termina com 0 erros, 0 warnings e 3
notes (as três descritas acima).

### Ordem sugerida de correção

1. Bloqueador 1 (`toupper()` no solver) — mudança de uma linha, destrava
   todo o fluxo de download.
2. Classificação de `302` como retentável + capacidade de o
   `.sicar_bootstrap()` renovar a sessão.
3. Timeouts de conexão/baixa velocidade adequados a arquivos grandes.
4. Pipeline de pré-processamento do solver Tesseract, revisado item a item
   contra a referência Python, até atingir o gate de 3/3 nos fixtures.
5. Achados menores, incluindo os testes offline que devem passar a
   simular a resposta real de CAPTCHA rejeitado.

## Status das correções (2026-09-21)

Todos os itens acima foram trabalhados nesta mesma sessão, na branch
`audit-fixes`. Resumo do que foi feito e o que ficou em aberto:

- **Bloqueador 1 (CAPTCHA case-sensitive) — corrigido.**
  `.sicar_normalize_solver_output()` não usa mais `toupper()`. Reverificado
  ao vivo pela API pública (sem patches): `sicar_download_state(client, "se",
  "AREA_POUSIO", ..., tries = 1)` teve sucesso na primeira tentativa usando o
  CAPTCHA exato lido (`sfvQ4`), baixando `SE_AREA_POUSIO.zip` (5 entradas).
- **Bloqueador 2 (solver Tesseract) — melhorado, não fechado.** Trocar
  `tessedit_pageseg_mode` de 7 para 8 (palavra única) elevou a acurácia nos 6
  fixtures da referência de 0/6 para 3/6, e nos 3 fixtures que o teste
  upstream de fato usa (`AbgBy`, `Ca7Qk`, `ZS7pc`), de 0/3 para 2/3. O erro
  remanescente é confusão de caractere (`Z` lido como `2`) que persistiu
  mesmo testando escala, padding, negativo e reordenação de kernel de
  morfologia — parece ser um limite do mecanismo LSTM do Tesseract disponível
  neste ambiente (o modo legado `oem 0` não tem `traineddata` instalado aqui
  para comparar). O solver continua documentado como experimental,
  recomendando o solver manual ou customizado onde acurácia importa.
- **302 retentável + sessão renovada — corrigido.** `.sicar_require_response()`
  agora trata `302` inesperado como retentável; `.sicar_attempt_download()`
  reseta `client$state$bootstrapped` nesse caso e chama `.sicar_bootstrap()`
  no início de cada tentativa, então a próxima tentativa renova a sessão
  automaticamente. Testado com mock de dois estágios em
  `test-download.R` (sessão expira na 1ª tentativa, recupera na 2ª).
- **Timeouts para arquivos grandes — corrigido.** `.sicar_request()` trocou o
  `timeout` total do curl por `connecttimeout` + `low_speed_time`/
  `low_speed_limit`, então uma transferência grande não é mais interrompida
  enquanto os dados continuam chegando.
- **Achados menores — corrigidos:** `@importFrom(stats, runif)`;
  `Depends: R (>= 4.1)` em `DESCRIPTION`; `LICENSE`/`LICENSE.md` trocados
  para o formato DCF esperado por `License: MIT + file LICENSE`;
  `NEWS.md` com cabeçalho `# rsicar 0.0.0.9000` (o texto anterior,
  `(development version)`, não é reconhecido pelo parser do
  `R CMD check`); `@examples` adicionados a todas as funções exportadas;
  validação de `client`/`dest_dir` em `sicar_download_country()`; estilo de
  mock HTTP unificado em `httr2::local_mocked_responses()` nos testes.
- **Código "morto" revisado com cuidado.** O bloco final inalcançável em
  `sicar_download_state()` foi removido. Já o fallback `writeBin()` em
  `.sicar_download_zip()` **não** era código morto — respostas mockadas via
  `httr2::local_mocked_responses()` não escrevem em `path =` durante
  `req_perform()`, então esse fallback é necessário tanto para os testes
  quanto para qualquer resposta real que não faça streaming. Ele foi mantido,
  com um comentário explicando o motivo.
- **Não feito nesta rodada:** adoção de `webfakes` para simular o protocolo
  completo (Fase 3 do plano). Os testes offline continuam usando
  `httr2::local_mocked_responses()`, que já cobre os casos de contrato
  reescritos (sessão expirada, CAPTCHA rejeitado); migrar para `webfakes`
  é uma tarefa de infraestrutura de teste maior e separada.

Resultado após as correções: `air format --check .` limpo, 57/57 testes
offline passam (eram 48), e `R CMD check` termina em **0 erros, 0 warnings,
0 notes** (eram 1 warning e 4/3 notes, dependendo da execução).

## Investigação adicional: solução automática de CAPTCHA (2026-09-21, continuação)

Depois das correções acima, testei se `sicar_solver_tesseract()` entrega uma
experiência "automática, simplesmente funciona" equivalente à que o pacote
Python oferece por padrão (o `Sicar()` do Python usa Tesseract por padrão,
sem exigir entrada manual). Duas frentes:

### Causa real da diferença de confiabilidade: `tries` e o tipo de backoff

O Python usa `tries=25` por padrão e um `sleep` curto e praticamente fixo
(`random.random() + random.random()`, ~0–2s) entre tentativas, **sem backoff
exponencial**, para qualquer motivo de falha — incluindo CAPTCHA errado. O
port R tinha `tries=3` e aplicava backoff exponencial (até 60s) mesmo para
"CAPTCHA errado, tenta de novo", que é um resultado rotineiro e esperado de
um solver automático, não um sinal de sobrecarga do servidor.

Corrigido: `.sicar_require_response()`/`.sicar_perform()` agora marcam
`slow_retry = TRUE` apenas para sinais reais de sobrecarga (408/429/5xx ou
falha de transporte/rede); CAPTCHA rejeitado (mismatch de `Content-Type`) e
sessão expirada (`302` inesperado) usam um atraso curto e quase fixo
(`.sicar_retry_delay(..., slow = FALSE)`), igual ao Python. O `tries` padrão
de `sicar_download_state()`/`sicar_download_country()` subiu de 3 para 25,
igualando o upstream. Coberto por testes novos em `test-http.R` e
`test-download.R` (retry rápido vs. exponencial, por classificação do erro).

### Acurácia do OCR em CAPTCHAs reais: pior que os fixtures, sem correção clara encontrada

Rodei o download real completo usando **somente** `sicar_solver_tesseract()`
(sem eu ler nenhum CAPTCHA), com o novo `tries=25`. Resultado: **falhou nas
25 tentativas**. Das 25, só 8 produziram uma saída de OCR com o formato
válido (5 caracteres alfanuméricos) — as outras 17 foram rejeitadas antes
mesmo de serem enviadas ao servidor por não terem esse formato — e nenhuma
das 8 enviadas correspondia ao CAPTCHA real.

Coletei 8 CAPTCHAs reais adicionais e comparei visualmente com os 6 fixtures
da referência: os reais são visivelmente mais difíceis (letras mais coladas,
traço de tachado mais grosso e irregular). Testei o pipeline já embarcado
(Otsu + morfologia + `psm 8`) contra esses 8, com gabarito lido visualmente
por mim: **1/8**, pior que os 3/6 medidos nos fixtures da referência — ou
seja, os fixtures cacheados da referência não representam bem a dificuldade
real atual do serviço.

Testei uma hipótese adicional própria (não usada pela referência Python):
remover o traço vermelho por cor (não por escala de cinza) antes do
pré-processamento, já que o traço é vermelho e o texto é preto — em teoria
mais fácil de segmentar por cor do que depois de tudo virar tons de cinza.
Visualmente a remoção funciona bem (as letras ficam bem mais legíveis a
olho). Mas combinada com o pipeline Otsu/morfologia já embarcado, o
resultado piorou (0/6 nos fixtures, 0/8 nos CAPTCHAs reais) — a etapa de
limiarização/morfologia existente parece ter sido implicitamente ajustada em
torno do padrão de ruído da linha vermelha original, e não se dá bem com a
imagem já limpa. Não fiz esse experimento avançar mais (testar um pipeline
desenhado do zero em torno da imagem sem vermelho) por não ter uma amostra
grande o bastante nem tempo de sessão para validar com confiança — descartei
essa mudança em vez de embarcar algo não verificado.

**Conclusão honesta:** a solução automática de CAPTCHA já existe e não exige
sessão interativa (isso só é necessário com `sicar_solver_manual()`, que é
opcional). Mas a acurácia por tentativa do solver Tesseract embarcado
continua baixa em CAPTCHAs reais atuais — mais baixa do que os fixtures da
referência sugeriam. A correção de `tries`/backoff é uma melhoria real e
verificada (mesma estratégia do Python), mas não é uma garantia: com a
acurácia observada, mesmo 25 tentativas podem falhar (como aconteceu numa
das execuções reais). Não encontrei, nesta sessão, uma correção de
pré-processamento que melhorasse isso de forma confiável.

**Duas variáveis que não pude testar neste ambiente:** (1) o motor legado do
Tesseract (`oem 0`) não tem `traineddata` instalado neste ambiente de teste
— só o motor LSTM (`oem 1`) — e é possível que o motor legado tenha
desempenho diferente nesta fonte estilizada; (2) a amostra de 8 CAPTCHAs
reais é pequena, então a acurácia medida (1/8) tem incerteza alta.

**Recomendação para quem depende de resolução automática confiável:**
implementar um `sicar_solver_function()` customizado chamando um serviço
pago de resolução de CAPTCHA (ex.: 2captcha, Anti-Captcha), o que é a
abordagem padrão de mercado para este tipo de CAPTCHA distorcido — a
interface do pacote já suporta isso sem mudanças. Alternativamente, testar
`sicar_solver_tesseract()` no ambiente real de uso (fora deste sandbox), já
que o motor Tesseract instalado pode se comportar diferente.
