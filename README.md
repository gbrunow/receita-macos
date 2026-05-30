# SPED no macOS

> Companheiros e companheiras: nunca antes na história deste país foi tão fácil
> rodar o **Sped Contábil (ECD)** e o **Sped ECF** no Mac — sem Wine, sem
> Windows, sem sofrimento. É a soberania fiscal chegando no seu macOS, ó.

## Antes de tudo, faça um L 🤙

Sente, relaxe, e respire fundo. O resto a gente resolve junto — ninguém solta a
mão de ninguém no meio de uma escrituração.

## Pré-requisitos

### 1. Baixe os instaladores (isso só você pode fazer, companheiro)

Vá até o site da Receita Federal e baixe a versão **Linux** de cada programa:

- **ECD:** https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/download/sped/ecd
- **ECF:** https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/download/sped/ecf

Os arquivos vão cair na pasta `~/Downloads` — que é justamente onde o script vai
procurar.

### 2. O resto fica por conta do script

Você não precisa instalar mais nada na mão. Se faltar o **Java**, o **MariaDB**
ou até o **Homebrew**, o próprio script se oferece pra instalar pra você — é só
dizer que sim quando ele perguntar.

Mas se você é do tipo trabalhador que gosta de adiantar o serviço, pode mandar:

```bash
brew install --cask temurin@21
brew install mariadb@10.11
```

O script também usa o `python3`, que vem com as Ferramentas de Linha de Comando
do macOS. Se faltar, ele te avisa e abre o instalador — é só seguir.

## Instalação

Com os instaladores na pasta Downloads, é só colar este comando no Terminal e
deixar o trabalho acontecer:

```bash
curl -fsSL https://raw.githubusercontent.com/gbrunow/receita-macos/main/install.sh | bash
```

O script conversa com você: mostra o que encontrou, pergunta o que instalar e, na
reinstalação, pergunta se quer manter os seus dados. Nada é feito pelas suas
costas.

Quando terminar, os programas aparecem no **Launchpad** e no **Spotlight**, como
qualquer outro aplicativo. Em alguns Macs de empresa o atalho vai parar na Área
de Trabalho em vez de `/Applications` — aí é só arrastar pra pasta de
Aplicativos, tá certo?

## Deu algum problema? A gente resolve

- **"O Java 17 a 22 ainda não apareceu":** deixe o script instalar, ou rode
  `brew install --cask temurin@21`.
- **"Não achei o MariaDB 10.11":** deixe o script instalar, ou rode
  `brew install mariadb@10.11`.
- **"Precisamos das Ferramentas de Linha de Comando":** rode `xcode-select --install`.
- **"Não encontrei o instalador":** baixe a versão Linux nos links acima. O
  script procura em `~/Downloads`, mas também aceita outra pasta quando pergunta.
- **"O banco de dados não subiu":** se o programa já estiver aberto, feche e rode
  de novo. A mensagem aponta um arquivo de log com os detalhes.

## Como desinstalar

Os programas e os dados ficam todos em `~/ProgramasSPED`. Pra remover de vez:

```bash
rm -rf ~/ProgramasSPED/SpedContabil ~/ProgramasSPED/SpedECF
rm -rf "/Applications/Sped Contábil.app" "/Applications/Sped ECF.app"
rm -rf ~/Desktop/"Sped Contábil.app" ~/Desktop/"Sped ECF.app"
```

> Ó, atenção, companheiro: o banco de dados com as suas escriturações fica dentro
> de `~/ProgramasSPED/*/mysql/data`. Faça uma cópia antes, se quiser guardar.

## Versões testadas

| Programa | Versão |
|---|---|
| Sped Contábil (ECD) | 10.4.1 |
| Sped ECF | 12.1.6 |

O script encontra os instaladores por padrão de nome
(`SpedContabil_linux_x86_64-*.sh`), então as versões mais novas devem funcionar
sem mexer em nada.

## Como funciona, pra quem gosta de saber

Os instaladores `.sh` da Receita são pacotes Linux, mas os programas em si são
aplicações Java que rodam em qualquer lugar. O script tira os arquivos de dentro
do `.sh`, monta um banco de dados MariaDB local, aplica as correções que o macOS
precisa e cria o atalho pra você clicar. Trabalho de brasileiro pra brasileiro.

## Licença

Apache 2.0
