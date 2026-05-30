# SPED no macOS

Instala o **Sped Contábil (ECD)** e o **Sped ECF** no macOS — Apple Silicon e Intel — sem Wine, sem Windows, sem sofrimento.

## Pré-requisitos

Antes de rodar o script, faça um L 🤙, sente e relaxe, e instale as dependências abaixo. Se já tiver o [Homebrew](https://brew.sh), basta copiar e colar no Terminal:

```bash
brew install --cask temurin@21
brew install mariadb@10.11
```

O script também usa `python3`, que já vem instalado no macOS (Monterey ou mais recente).

## Baixe os instaladores

Acesse o site da Receita Federal e baixe a versão **Linux** de cada programa:

- **ECD:** https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/download/sped/ecd
- **ECF:** https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/download/sped/ecf

Os arquivos vão parar em `~/Downloads` — que é exatamente onde o script vai procurá-los.

## Instalação

Com os instaladores na pasta Downloads, rode o comando abaixo no Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/gbrunow/receita-macos/main/install.sh | bash
```

O script vai encontrar os arquivos, confirmar o que vai instalar e cuidar do resto.

Após a instalação, os programas ficam disponíveis no **Launchpad** e no **Spotlight**. Em alguns Macs corporativos, o atalho é criado na Área de Trabalho em vez de `/Applications` — basta arrastá-lo para a pasta de Aplicativos.

## Versões compatíveis

| Programa | Versão testada |
|---|---|
| Sped Contábil (ECD) | 10.4.1 |
| Sped ECF | 12.1.6 |

O script usa glob para encontrar os instaladores (`SpedContabil_linux_x86_64-*.sh`), então versões mais novas devem funcionar sem alteração.

## Como funciona

Os instaladores `.sh` da Receita Federal são pacotes Linux, mas os programas em si são aplicações Java que rodam em qualquer plataforma. O script extrai os arquivos diretamente do `.sh`, configura um banco de dados MariaDB local, aplica correções de compatibilidade necessárias para o macOS e cria um atalho clicável.

## Licença

Apache 2.0
