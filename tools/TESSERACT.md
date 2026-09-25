# Desenvolvimento e avaliação do solver Tesseract

Execute os comandos na raiz do repositório. Os benchmarks são offline;
somente `collect-captchas.R` acessa o SICAR, com ativação explícita.

## Coletar e revisar a amostra

Para aproveitar downloads normais, crie o solver com
`sicar_solver_tesseract(diagnostics_dir = ".scratch/captcha-corpus")`.
Cada chamada salva um PNG e um JSON com candidatos, confiança, seleção,
tempos e versões. Respostas incompletas são mantidas. Uma alternativa é uma
coleta dedicada de até 100 imagens, sequencial e com intervalo de dois segundos:

```sh
RSICAR_RUN_LIVE_TESTS=true Rscript --no-init-file tools/collect-captchas.R 100 .scratch/captcha-corpus
Rscript --no-init-file tools/prepare-captcha-corpus.R .scratch/captcha-corpus
```

O segundo comando cria `manifest.csv` e `label-development.html`. Abra o HTML
no navegador, transcreva os cinco caracteres preservando maiúsculas e
minúsculas e exporte o CSV. Substitua o manifesto da pasta pelo exportado.
Deixe respostas ambíguas vazias: o benchmark informa quantas foram excluídas.
A página não mostra previsões do OCR. Ela funciona offline e permite importar
um CSV para continuar a revisão. Exporte antes de fechar; respostas não são
gravadas automaticamente.

O manifesto tem as colunas `id,path,expected,split,protect`. Os caminhos são
relativos ao CSV; rótulos nunca são inferidos dos nomes dos arquivos nem do
OCR. `protect=TRUE` marca um caso que deve continuar resolvido. Cerca de 20%
das novas imagens são reservadas para `evaluation` por hash, independentemente
do resultado do OCR. A atribuição permanece estável quando a amostra cresce.
Imagens repetidas são deduplicadas na preparação e rejeitadas no benchmark,
inclusive se tiverem nomes diferentes ou estiverem em divisões diferentes.

As nove fixtures já usadas para ajustar o solver estão todas em `development`.
A coleta de 2026-09-25 contém 100 PNGs em `.scratch/captcha-corpus-2026-09-25`,
com 78 em desenvolvimento e 22 reservados. Seus rótulos começam vazios.
Essa coleta de uma única sessão ainda não representa variações ao longo dos dias.

## Ajustar e congelar uma configuração

```sh
make ocr-benchmark
# Ou, depois de revisar os novos rótulos:
make ocr-benchmark OCR_MANIFEST=.scratch/captcha-corpus/manifest.csv OCR_OUTPUT=.scratch/ocr-development
```

Use uma pasta de saída vazia para cada execução. O modo `tune` lê somente
imagens rotuladas de desenvolvimento. Compara PSM 7, 8 e 13; dicionários ligados
ou desligados; bordas brancas de 0 ou 10 pixels; e margens de confiança de
0, 10, 20, 30, 40, 50 e 101 pontos. Os candidatos são reaproveitados ao variar
a margem, evitando novas chamadas de OCR.

Arquivos produzidos:

- `candidates.csv`: as duas leituras e seus tempos para cada configuração OCR.
- `predictions.csv`: resposta escolhida e acerto exato por imagem/configuração.
- `summary.csv`: acerto, respostas válidas, tempo e regressões em casos protegidos.
- `environment.json`: versões, hash de `eng.traineddata`, imagens usadas e rótulos ausentes.
- `frozen-config.json`: configuração escolhida usando apenas desenvolvimento.

`oracle_correct` conta imagens em que algum dos dois candidatos estava correto.
`selection_missed` conta oportunidades perdidas pela regra de escolha. Isso
ajuda a distinguir problemas de reconhecimento e de seleção. A escolha da
configuração protege os casos explicitamente marcados e todos os que o solver
atual acertou. Em empates, prefere menos mudanças nos parâmetros atuais.
Se nenhuma configuração preservar os casos protegidos, não gera configuração
congelada; consulte `protected_failures` e `predictions.csv`.

Na comparação inicial das nove fixtures com Tesseract 5.3.2, o melhor resultado
foi 7/9. Desativar dicionários empatou e as bordas/modos alternativos pioraram.
O resultado selecionou os parâmetros atuais: PSM 7, dicionários ligados,
borda zero e margem 30. Esse é um resultado de desenvolvimento, não uma
estimativa independente da taxa de acerto.

Uma comparação controlada com o executável Tesseract 5.5.3, usando as mesmas
imagens processadas, parâmetros e `eng.traineddata` (MD5
`d1be414fbb296b3ad777bfca655e194e`), acertou 4/9, contra 7/9 da biblioteca
5.3.2 usada pelo R. Portanto, não basta fixar as imagens: uma mudança no motor
também deve passar pelo benchmark e pela checagem dos casos protegidos.

## Avaliar imagens reservadas

Depois de congelar a configuração, gere a página de revisão das imagens
reservadas e exporte os rótulos para o mesmo manifesto:

```sh
Rscript --no-init-file tools/prepare-captcha-corpus.R .scratch/captcha-corpus evaluation .scratch/ocr-development/frozen-config.json
Rscript --no-init-file tools/benchmark-tesseract.R evaluate .scratch/captcha-corpus/manifest.csv .scratch/ocr-evaluation .scratch/ocr-development/frozen-config.json
```

`evaluate` executa somente a configuração congelada. Recusa imagens que já
participaram do ajuste, mesmo vindas de outro manifesto. Se usar os resultados
da avaliação para ajustar novamente o solver, reserve novas imagens para uma
avaliação independente.

## Comparar versões e downloads reais

```sh
make ocr-regression
```

Esse teste opcional confere cada caso protegido na instalação atual, sem fixar
uma versão do Tesseract ou exigir um total exato de acertos. Execute também o
benchmark em cada ambiente: versão do motor e hash do modelo são necessários
para interpretar diferenças. A suíte padrão testa a escolha dos candidatos,
a separação dos dados e os diagnósticos sem exigir previsões idênticas de OCR.

Para medir downloads reais, prepare um CSV `id,attempts,success`, com uma linha
por download solicitado e incluindo falhas (`success=FALSE`). Registre o total
real de tentativas, sem contar arquivos já existentes como sucessos do solver:

```sh
Rscript --no-init-file tools/benchmark-tesseract.R downloads runs.csv .scratch/ocr-downloads
```

O resumo usa todos os downloads como denominador para sucesso na primeira,
até a terceira e até a quinta tentativa. Não deriva essas taxas da acurácia
offline. Diagnósticos de OCR não fornecem sozinhos o resultado do download;
o manifesto normal de downloads registra apenas os sucessos, portanto precisa
ser complementado com as falhas para esta análise.
