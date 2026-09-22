rsicar
================

# rsicar

Cliente R nativo para consultar e baixar dados públicos do Sistema
Nacional de Cadastro Ambiental Rural (SICAR).

## Atribuição e proveniência

O `rsicar` é uma implementação nativa em R inspirada e portada a partir
do pacote Python [SICAR](https://github.com/urbanogilson/SICAR),
desenvolvido por [Gilson Urbano](https://github.com/urbanogilson). A API
e a implementação foram adaptadas para as convenções do R, mas o fluxo
essencial de consulta e download do SICAR foi desenvolvido tendo esse
projeto como referência.

Este porte usa como referência o commit
`facffbf91a4998a2daa814a65d1d36ea99266f83` do projeto Python. O projeto
original é distribuído sob a licença MIT; sua atribuição e o texto da
licença estão preservados em [LICENSE.md](LICENSE.md).

## Instalação

``` r
remotes::install_github("kguidonimartins/rsicar")
```

O solver manual e os solvers definidos pelo usuário funcionam sem
dependências de OCR. Para testar o solver experimental Tesseract,
instale também os pacotes opcionais `magick` e `tesseract` e o programa
Tesseract no sistema.

## Uso

O construtor não acessa a rede. A sessão HTTPS e o cookie jar são
inicializados somente na primeira operação que consulta o SICAR.

``` r
client <- sicar_client(solver = sicar_solver_manual())
sicar_states()[1:5]
#> [1] "AC" "AL" "AM" "AP" "BA"
sicar_polygon_types()
#> [1] "AREA_IMOVEL"             "APPS"                   
#> [3] "VEGETACAO_NATIVA"        "AREA_CONSOLIDADA"       
#> [5] "AREA_POUSIO"             "HIDROGRAFIA"            
#> [7] "USO_RESTRITO"            "SERVIDAO_ADMINISTRATIVA"
#> [9] "RESERVA_LEGAL"
```

Para consultar as datas de disponibilização:

``` r
dates <- sicar_release_dates(client)
head(dates)
```

Para baixar um estado, o CAPTCHA pode ser resolvido manualmente: a
imagem é aberta automaticamente no visualizador padrão do sistema
(macOS, Linux e Windows) antes de pedir a resposta no console:

``` r
sicar_download_state(
  client,
  state = "PA",
  polygon = "APPS",
  dest_dir = "SICAR/PA"
)
```

`polygon` aceita um vetor com mais de um tipo; todos os valores são
validados antes de iniciar qualquer download:

``` r
sicar_download_state(
  client,
  state = "PA",
  polygon = c("APPS", "RESERVA_LEGAL"),
  dest_dir = "SICAR/PA"
)
```

Cada download bem-sucedido é registrado em um `manifest.json` dentro de
`dest_dir`, com estado, tipo de polígono, tamanho e checksum MD5 do
arquivo, data/hora, solver de CAPTCHA utilizado e número de tentativas.
Use `sicar_read_manifest()` para ler esse arquivo e
`sicar_download_status()` (ou `sicar_download_country_status()`, para
uma árvore inteira de `sicar_download_country()`) para diagnosticar o
que falta baixar — por exemplo, depois que um solver esgotou as
tentativas em algum polígono:

``` r
sicar_read_manifest("SICAR/PA")
sicar_download_status("SICAR/PA")
```

Para selecionar as geometrias que tocam um ou mais municípios a partir
dos ZIPs já baixados, resolva os municípios pelos nomes ou códigos IBGE
e passe um ZIP ou uma pasta de origem. A função retorna um objeto `sf`
sem recortar as geometrias e sem gravar arquivos automaticamente. Na
primeira extração, a malha municipal de 2025 é baixada pelo pacote
opcional `geobr` e armazenada no cache local do usuário; as chamadas
seguintes reutilizam esse cache:

``` r
sicar_resolve_municipality(c("Recife", "Olinda", "Paulista/PE"))

features <- sicar_extract_municipality(
  c("Recife", "Olinda"),
  src_dir = "SICAR/PE"
)
sf::st_write(features, "minha-aoi.gpkg")
```

Consulte as vignettes para configurar solvers customizados, entender as
garantias de validação dos arquivos baixados e ler o [dicionário
completo dos dados do
CAR](https://kguidonimartins.github.io/rsicar/articles/car-data.html),
com os campos, códigos, temas espaciais, unidades e cautelas para
análise.

## Status

O pacote está em desenvolvimento. O solver Tesseract é experimental até
passar o gate de acurácia definido no plano do projeto; solver manual e
solver customizado são suportados desde já.
