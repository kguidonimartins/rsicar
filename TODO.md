# Extração de AOIs municipais a partir dos dados do SICAR

Status: planejamento registrado; nenhuma implementação desta funcionalidade foi
iniciada.

## Entendimento do objetivo

O SICAR não oferece download diretamente por município. O fluxo desejado é:

1. o usuário baixa, por estado e tema, os ZIPs disponibilizados pelo SICAR;
2. informa um ou mais municípios por identificador aceito pelo pacote;
3. o pacote resolve esses identificadores para códigos municipais de sete
   dígitos do IBGE;
4. o pacote lê as geometrias municipais de referência, seleciona as feições dos
   dados do SICAR que tocam os limites dos municípios e preserva as geometrias
   completas das feições selecionadas;
5. o resultado é retornado diretamente como um objeto `sf`; a persistência em
   GeoPackage fica sob controle do usuário, por exemplo com `sf::st_write()`.

A seleção espacial deve usar `sf::st_intersects()`, nunca
`sf::st_intersection()`: a saída não deve recortar, alterar ou substituir a
geometria original do SICAR. Para vários municípios, uma feição do SICAR que
toque mais de um município deve ser mantida uma única vez, salvo decisão
contrária no contrato final.

## [x] 1 — Fechar o contrato da API antes do código

- [x] Adotar `sicar_resolve_municipality()` como nome da função pública de resolução e
  retornar um vetor de códigos IBGE como texto, com sete dígitos.
- [x] Reproduzir a compatibilidade com `geofbds::fbds_resolve()`: códigos IBGE,
  nomes sem acento e sem distinção de caixa, `Municipio/UF`, sigla de UF,
  desambiguação por `uf`, `strict` e preservação da ordem sem duplicatas.
- [x] Adotar `sicar_extract_municipality(x, src_dir, ...)` como função de
  extração. Se `src_dir` for uma pasta, todos os arquivos `.zip` encontrados
  nela serão processados; se for um arquivo `.zip`, somente ele será usado.
- [x] A função não gravará GeoPackage nem outro arquivo. Os argumentos
  `dest_dir` e `file_name` não fazem parte do contrato; a função retornará
  diretamente um objeto `sf` com as feições selecionadas.
- [x] Buscar recursivamente todos os arquivos `.zip` abaixo de uma pasta
  indicada, incluindo as subpastas de estados criadas por
  `sicar_download_country()`.
- [x] Retornar somente os atributos e geometrias originais do SICAR, sem
  acrescentar metadados de origem ou de município ao objeto retornado.
- [x] Definir o comportamento para ausência de feições, ZIPs incompletos,
  camadas incompatíveis, CRS ausente/diferente e geometrias inválidas.

Contrato adicional para a implementação: ausência do caminho de origem ou de
ZIPs processáveis deve gerar erro `rsicar_invalid_argument` ou
`rsicar_source_error`; uma origem válida sem feições que intersectem os
municípios deve retornar um objeto `sf` vazio, mantendo o esquema espacial
compatível quando isso for possível. Erros de leitura, CRS ausente ou
geometria inválida devem interromper a operação com condições `rsicar_*` e
contexto suficiente para identificar o arquivo.

### 1.1 — Contrato confirmado pelo exemplo de `fbds_resolve()`

- [x] A entrada aceita um vetor heterogêneo de identificadores; cada elemento
  pode ser código IBGE, nome municipal ou `nome/UF`.
- [x] A comparação de nomes ignora acentos e caixa, de modo que, por exemplo,
  `sao lourenco da mata` resolve o mesmo município que `São Lourenço da
  Mata`.
- [x] Um nome existente em mais de uma UF não é escolhido arbitrariamente:
  `araçoiaba` deve gerar erro ambíguo, informando as UFs candidatas e
  orientando o uso de `araçoiaba/PE` ou do argumento `uf`.
- [x] A forma `nome/UF` desambigua o município, como em `paulista/PE`,
  `goiana/PE` e `Passos/MG`.
- [x] Uma chamada com qualquer identificador ambíguo ou inválido falha sem
  retornar um vetor parcial.
- [x] Em uma chamada válida, o resultado é um vetor de códigos IBGE em texto,
  na ordem da primeira ocorrência e sem duplicatas; a função não retorna a
  tabela municipal completa.
- [x] Reproduzir também o texto final das mensagens e as classes
  `rsicar_*`, adaptando somente o prefixo de condição ao padrão deste pacote.

Exemplos de aceite para a implementação:

```r
sicar_resolve_municipality(c("recife", "olinda", "paulista/PE", "Passos/MG"))
#> c("2611606", "2609600", "2610707", "3147907")

sicar_resolve_municipality("araçoiaba")
#> erro rsicar_ambiguous_municipality, com candidatos "CE" e "PE"

sicar_resolve_municipality("araçoiaba/PE")
#> "2601052"
```

## [x] 2 — Inventariar a integração com os downloads existentes

- [x] Confirmar a estrutura de entrada suportada pela função: um arquivo `.zip`
  ou uma pasta contendo ZIPs; a inspeção dos shapefiles internos ficará na
  tarefa de leitura espacial, porque o repositório não contém ZIPs reais do
  SICAR.
- [x] Mapear os caminhos produzidos por `sicar_download_state()` e
  `sicar_download_country()` (`dest_dir/<UF>/<UF>_<TEMA>.zip`) e aceitar tanto
  uma pasta de ZIPs quanto um ZIP avulso como origem.
- [x] Definir leitura segura em diretório temporário, sem alterar os ZIPs
  originais e sem deixar arquivos extraídos no repositório ou em `R/`.
- [x] Reutilizar a validação existente de ZIP e distinguir erros de arquivo,
  camada, leitura espacial e seleção vazia com condições `rsicar_*` úteis.

## 3 — Incorporar a malha municipal de referência

- [ ] Criar um script reprodutível em `data-raw/` que execute
  `geobr::read_municipality(year = 2025, simplified = FALSE)` com progresso
  desativado durante a geração do artefato.
- [ ] Manter no artefato somente as colunas necessárias para resolução e
  interseção, preservando os códigos IBGE como texto de sete dígitos, os nomes,
  as UFs e a coluna de geometria.
- [ ] Registrar no script e na documentação a fonte `geobr`, o ano de
  referência, a data/versão usada para gerar o artefato, o CRS e qualquer
  transformação aplicada.
- [ ] Escolher e justificar o armazenamento como dado interno do pacote
  (`R/sysdata.rda`) ou como dataset do pacote (`data/*.rda`), seguindo a
  distinção de dados internos e dados disponíveis ao usuário em
  <https://r-pkgs.org/data.html>.
- [ ] Medir o tamanho comprimido do artefato, verificar o impacto no tamanho do
  pacote e testar que ele é carregado com `devtools::load_all()` e após a
  instalação.
- [ ] Não baixar a malha do `geobr` em tempo de execução: a função pública deve
  usar o artefato integrado e determinístico.

## 4 — Implementar o resolvedor municipal

- [ ] Implementar a normalização e validação dos identificadores contra o
  catálogo municipal integrado.
- [ ] Suportar um ou mais códigos IBGE, nomes canônicos sem acento e sem
  distinção de caixa, `Municipio/UF`, siglas de UF e o argumento opcional `uf`.
- [ ] Reproduzir a política de ambiguidade de `fbds_resolve()`: nunca resolver
  silenciosamente um nome presente em mais de uma UF.
- [ ] Criar condições de erro `rsicar_*` para entrada inválida, município
  desconhecido e nome ambíguo, com os candidatos e a entrada original como
  contexto.
- [ ] Garantir retorno determinístico, na ordem da primeira ocorrência e sem
  códigos duplicados; definir o comportamento de `strict = FALSE`.
- [ ] Documentar e exportar a função, com exemplos totalmente offline.

## 5 — Implementar a seleção espacial da AOI

- [ ] Resolver os municípios e extrair suas geometrias da malha de 2025.
- [ ] Ler as feições dos ZIPs selecionados como `sf`, preservando todos os
  atributos e a geometria original do SICAR.
- [ ] Validar CRS em ambos os objetos e transformar a malha municipal para o
  CRS das feições do SICAR quando necessário, sem desativar a validação
  espacial do `sf`.
- [ ] Calcular a relação espacial exclusivamente com `sf::st_intersects()`;
  converter os índices retornados em uma seleção de linhas e nunca chamar
  `sf::st_intersection()`.
- [ ] Deduplicar feições quando elas tocarem mais de um município, mantendo
  uma linha por feição original, e definir como registrar a associação com
  vários municípios caso esse metadado seja incluído.
- [ ] Definir tratamento explícito para feições inválidas, geometrias vazias,
  CRS ausente, resultado sem feições e diferenças de precisão entre limites.

## 6 — Retornar as geometrias selecionadas

- [ ] Retornar um objeto `sf` com as feições originais do SICAR que
  intersectam pelo menos um município solicitado.
- [ ] Preservar atributos, geometria e CRS das feições de origem; a função não
  deve recortar, transformar permanentemente ou gravar as geometrias.
- [ ] Definir se o retorno conterá metadados de origem e de município, conforme
  a decisão do contrato sobre atributos adicionais.
- [ ] Garantir que o resultado possa ser gravado pelo usuário posteriormente
  com `sf::st_write()` caso deseje persistir a AOI.

## 7 — Criar testes offline

- [ ] Adicionar fixtures espaciais pequenos e determinísticos para município,
  feição que cruza o limite, feição que apenas toca o limite, feição fora da
  AOI e feição que toca dois municípios.
- [ ] Testar o resolvedor para códigos, nomes, acentos, UF, ambiguidade,
  desconhecidos, entradas vazias, duplicatas e `strict`.
- [ ] Testar que `st_intersects()` seleciona a feição completa e que a
  geometria de saída é igual à geometria de origem, sem recorte.
- [ ] Testar múltiplos municípios, deduplicação, CRS diferente, ausência de CRS,
  resultado vazio, ZIP inválido e camada espacial ausente.
- [ ] Verificar diretamente o objeto `sf` retornado: geometria, atributos,
  CRS, número de feições, deduplicação e ausência de recorte geométrico.
- [ ] Manter os testes padrão sem rede; usar `skip_if_not_installed("sf")` para
  testes que dependam da sugestão opcional e evitar sleeps reais.

## 8 — Finalizar documentação, pacote e critérios de aceite

- [ ] Atualizar `DESCRIPTION` com as dependências corretas, mantendo `sf` e
  demais dependências pesadas opcionais quando possível; `geobr` deve ser
  necessário para regenerar o artefato, não para a consulta em tempo de
  execução.
- [ ] Adicionar documentação roxygen, referências cruzadas, exemplos offline,
  vignette de fluxo download → AOI e entrada pública no `_pkgdown.yml`.
- [ ] Atualizar `README.Rmd`, `NEWS.md` e, quando a API estiver fechada, o
  `PLAN.md`; nunca editar `README.md` diretamente.
- [ ] Rodar `make format`, `make document`, `make tests`, `make check` e os
  exemplos, registrando qualquer limitação da instalação local.
- [ ] Critérios de aceite: resolução determinística de municípios; seleção por
  `st_intersects()`; nenhuma geometria alterada por interseção geométrica;
  retorno `sf` reprodutível; preservação dos ZIPs existentes; suíte padrão
  offline; e malha municipal de 2025 reproduzível a partir de `data-raw/`.

## 9 — Registrar dependências e pontos de atenção

- `geobr::read_municipality()` será usado na geração dos dados integrados, com
  `year = 2025` e `simplified = FALSE`.
- `sf` será usado em tempo de execução para leitura, transformação, interseção
  e escrita; a posição em `Imports` ou `Suggests` deve ser decidida conforme a
  política final de dependências do pacote.
- A geração da malha pode exigir rede e versões específicas de `geobr`, mas
  isso não pode tornar a resolução ou os testes padrão dependentes de rede.
- O comportamento de limites compartilhados e a deduplicação são importantes:
  `st_intersects()` considera contato de fronteira, exatamente como requerido,
  e a saída não deve multiplicar uma feição apenas porque ela atende a vários
  municípios.
- geometrias inválidas podem ser tratadas com `sf::st_make_valid`. se alguma
  geometria inválida for detectada, corrija e avise ao usuário quantas foram
  corrigidas. 
