#!/bin/bash
# install.sh — Instala o SPED ECD e/ou ECF no macOS (Apple Silicon e Intel)
#
# Pré-requisitos:
#   - Java 17-22       brew install --cask temurin@21
#   - MariaDB 10.11    brew install mariadb@10.11
#   - python3          (já incluso no macOS via Command Line Tools)
#
# Uso rápido:
#   curl -fsSL https://raw.githubusercontent.com/gbrunow/receita-macos/main/install.sh | bash

set -euo pipefail

# ── Constantes ────────────────────────────────────────────────────────────────

INSTALL_BASE="$HOME/ProgramasSPED"
DEFAULT_SEARCH_DIR="$HOME/Downloads"

# Senha do banco embutido. É definida pelo próprio aplicativo da Receita (SERPRO),
# não pelo projeto — o PVA se conecta com ela. O script LÊ a senha da configuração
# embarcada no app (read_db_password) para resistir a mudanças em versões futuras.
# Este valor é o fallback: foi a senha observada nas versões já extraídas
# (ECD 10.4.1, ECF 12.1.6) e é usada apenas se a leitura dinâmica falhar.
DB_PASSWORD_FALLBACK="toor321"

ECD_GLOB="SpedContabil_linux_x86_64-*.sh"
ECF_GLOB="SpedECF_linux_x86_64-*.sh"
ECD_NAME="Sped Contábil (ECD)"
ECF_NAME="Sped ECF"
ECD_APP_DIR="$INSTALL_BASE/SpedContabil"
ECF_APP_DIR="$INSTALL_BASE/SpedECF"
ECD_MAIN_CLASS="install4j.br.gov.serpro.sped.contabil.pva.fronteira.ppgd.PgdApp"
ECF_MAIN_CLASS="install4j.br.gov.serpro.sped.irpjpva.fronteira.ppgd.PgdApp"
ECD_URL="https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/download/sped/ecd"
ECF_URL="https://www.gov.br/receitafederal/pt-br/centrais-de-conteudo/download/sped/ecf"

MARIADB_BIN=""              # set by check_prereqs
DETECTED_JAVA_HOME=""       # set by check_prereqs (validated 17-22 JDK)
ECD_INSTALLER=""            # set by discover_installers
ECF_INSTALLER=""            # set by discover_installers
INSTALLED=()                # app dirs installed this run

# Largura do terminal para alinhamento (mín. com fallback 80, nunca acima de 80)
TERM_COLS=$(tput cols 2>/dev/null || echo 80)
[[ "$TERM_COLS" =~ ^[0-9]+$ ]] || TERM_COLS=80
[[ "$TERM_COLS" -gt 80 ]] && TERM_COLS=80

# ── Saída ─────────────────────────────────────────────────────────────────────

ok()   { echo "  ✓ $*"; }
nok()  { echo "  ✗ $*"; }
info() { echo "  → $*"; }
fail() { echo; echo "  Erro: $*" >&2; exit 1; }
ask()  { read -r -p "  $* " reply < /dev/tty; echo "$reply"; }

# Linha horizontal que respeita a largura do terminal
hr() { printf '  '; printf '━%.0s' $(seq 1 $(( TERM_COLS - 2 ))); echo; }

# Step label alinhado para um ✓/✗ ao final, na coluna TERM_COLS
step()      { printf "  → %s" "$*"; }
step_ok()   { printf "\033[%sG✓\n" "$TERM_COLS"; }
step_fail() { printf "\033[%sG✗\n" "$TERM_COLS"; }

# Cabeçalho de seção preenchido com ─ até a largura do terminal
section_header() {
  local line="  ── $* ──"
  local chars
  chars=$(printf '%s' "$line" | wc -m | xargs)
  printf '%s' "$line"
  local fill=$(( TERM_COLS - chars ))
  [[ $fill -gt 0 ]] && printf '─%.0s' $(seq 1 "$fill")
  echo
}

# ── Pré-requisitos ────────────────────────────────────────────────────────────

# Versão "feature" do Java instalado (trata o esquema legado 1.x → 8). Vazio se ausente.
java_feature_version() {
  command -v java >/dev/null 2>&1 || return 0
  local v
  v=$(java -version 2>&1 | awk -F'"' '/version/ {print $2}')
  if [[ "$v" == 1.* ]]; then echo "$v" | cut -d. -f2; else echo "$v" | cut -d. -f1; fi
}

java_in_range() {
  local v; v=$(java_feature_version)
  [[ "$v" =~ ^[0-9]+$ && "$v" -ge 17 && "$v" -le 22 ]]
}

# Coloca o brew no PATH da sessão atual (Apple Silicon ou Intel)
load_brew_env() {
  if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew   ]]; then eval "$(/usr/local/bin/brew shellenv)"
  fi
}

# Instala um pacote do Homebrew com confirmação (padrão: sim)
brew_install() {
  local label="$1"; shift
  echo
  local r; r=$(ask "Companheiro, posso instalar $label agora? [S/n]")
  [[ "$r" =~ ^[Nn]$ ]] && fail "Ó, sem $label não dá pra seguir. Instale com: $* — e rode o script de novo."
  info "Tô instalando $label pra você. Isso leva uns minutinhos, tenha paciência..."
  if "$@"; then ok "$label instalado, com o trabalho do povo brasileiro"; else fail "Não consegui instalar $label, companheiro. Tente na mão: $*"; fi
}

ensure_homebrew() {
  command -v brew >/dev/null 2>&1 && return 0
  load_brew_env
  command -v brew >/dev/null 2>&1 && return 0
  echo
  info "Companheiro, o Homebrew é necessário e ainda não tá instalado aqui."
  local r; r=$(ask "Posso instalar o Homebrew agora? Talvez ele peça a senha do seu Mac. [S/n]")
  [[ "$r" =~ ^[Nn]$ ]] && fail "Sem o Homebrew não tem como, companheiro. Instale em https://brew.sh e volte aqui."
  info "Tô instalando o Homebrew. Isso leva uns minutinhos, fica tranquilo..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
  load_brew_env
  command -v brew >/dev/null 2>&1 || fail "Não consegui instalar o Homebrew, companheiro. Instale em https://brew.sh"
  ok "Homebrew instalado, tá certo"
}

# Garante todos os pré-requisitos, instalando o que faltar.
ensure_prereqs() {
  local brew_prefix java_ver

  ensure_homebrew
  brew_prefix=$(brew --prefix 2>/dev/null)

  # Java 17-22
  if ! java_in_range; then
    brew_install "o Java (Temurin 21)" brew install --cask temurin@21
    java_in_range \
      || fail "O Java 17 a 22 ainda não apareceu, companheiro. Abra um Terminal novo e rode o script de novo."
  fi
  java_ver=$(java_feature_version)
  # Fixa a JVM validada para o launcher (evita que um JDK 23+ instalado depois quebre o app)
  DETECTED_JAVA_HOME=$(/usr/libexec/java_home -v "$java_ver" 2>/dev/null || true)

  # MariaDB 10.11
  MARIADB_BIN="$brew_prefix/opt/mariadb@10.11/bin"
  if [[ ! -x "$MARIADB_BIN/mysqld" ]]; then
    brew_install "o MariaDB 10.11" brew install mariadb@10.11
    brew_prefix=$(brew --prefix 2>/dev/null)
    MARIADB_BIN="$brew_prefix/opt/mariadb@10.11/bin"
    [[ -x "$MARIADB_BIN/mysqld" ]] || fail "Não achei o MariaDB 10.11 depois de instalar, companheiro."
  fi

  # python3 (vem com as Ferramentas de Linha de Comando do Xcode)
  if ! command -v python3 >/dev/null 2>&1; then
    echo
    info "Companheiro, precisamos das Ferramentas de Linha de Comando (o python3)."
    info "Vou abrir o instalador do macOS — conclua ali na janela que aparecer, tá?"
    xcode-select --install 2>/dev/null || true
    fail "Quando terminar de instalar as Ferramentas de Linha de Comando, rode o script de novo, companheiro."
  fi

  ok "Tá tudo pronto, companheiro: Java $java_ver e MariaDB 10.11"
}

# ── Descoberta de instaladores ────────────────────────────────────────────────

# Retorna o arquivo mais recente que casa com o glob, ou vazio. Nunca falha
# (importante sob set -e + pipefail: 'ls' de um glob sem match retorna não-zero).
find_in_dir() {
  local dir="$1" glob="$2"
  # shellcheck disable=SC2086
  ls -t "$dir"/$glob 2>/dev/null | head -1 || true
}

resolve_path() {
  local input="$1" glob="$2"
  input="${input/#\~/$HOME}"
  if   [[ -f "$input" ]]; then echo "$input"
  elif [[ -d "$input" ]]; then find_in_dir "$input" "$glob"
  fi
}

# Pergunta um caminho alternativo. Mensagens de erro vão para STDERR para não
# contaminarem o valor capturado por command substitution.
ask_custom_path() {
  local label="$1" glob="$2"
  local input resolved
  input=$(ask "O instalador do $label tá em outra pasta, companheiro? Informe o caminho (ou Enter pra pular):")
  [[ -z "$input" ]] && return 0
  resolved=$(resolve_path "$input" "$glob")
  if [[ -n "$resolved" ]]; then
    echo "$resolved"
  else
    echo "  ✗ Não encontrei o instalador do $label nessa pasta, companheiro. Esse programa não vai ser instalado." >&2
  fi
}

discover_installers() {
  local search_dir="${1:-$DEFAULT_SEARCH_DIR}"

  echo
  info "Vou procurar os instaladores em $search_dir..."
  echo

  ECD_INSTALLER=$(find_in_dir "$search_dir" "$ECD_GLOB")
  ECF_INSTALLER=$(find_in_dir "$search_dir" "$ECF_GLOB")

  [[ -n "$ECD_INSTALLER" ]] && ok "ECD: $(basename "$ECD_INSTALLER")" || nok "ECD: não encontrei, companheiro"
  [[ -n "$ECF_INSTALLER" ]] && ok "ECF: $(basename "$ECF_INSTALLER")" || nok "ECF: não encontrei, companheiro"

  # Nada encontrado — pede outra pasta ou encerra
  if [[ -z "$ECD_INSTALLER" && -z "$ECF_INSTALLER" ]]; then
    echo
    info "Ó, os instaladores você baixa no site da Receita Federal, na versão Linux:"
    info "  ECD: $ECD_URL"
    info "  ECF: $ECF_URL"
    echo
    local custom_dir
    custom_dir=$(ask "Em qual pasta tão os instaladores, companheiro?")
    if [[ -z "$custom_dir" ]]; then
      echo
      info "Não selecionamos nenhum instalador, companheiro. Baixe os arquivos e rode o script de novo."
      exit 0
    fi
    discover_installers "${custom_dir/#\~/$HOME}"
    return
  fi

  # Pede caminho para os que faltam
  echo
  [[ -z "$ECF_INSTALLER" ]] && ECF_INSTALLER=$(ask_custom_path "$ECF_NAME" "$ECF_GLOB")
  [[ -z "$ECD_INSTALLER" ]] && ECD_INSTALLER=$(ask_custom_path "$ECD_NAME" "$ECD_GLOB")

  # Confirmação
  echo
  if [[ -n "$ECD_INSTALLER" && -n "$ECF_INSTALLER" ]]; then
    local confirm
    confirm=$(ask "Vamo instalar os dois, companheiro? [S/n]")
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
      local c_ecd c_ecf
      c_ecd=$(ask "Vamo instalar o $ECD_NAME? [S/n]")
      [[ "$c_ecd" =~ ^[Nn]$ ]] && ECD_INSTALLER=""
      c_ecf=$(ask "Vamo instalar o $ECF_NAME? [S/n]")
      [[ "$c_ecf" =~ ^[Nn]$ ]] && ECF_INSTALLER=""
    fi
  elif [[ -n "$ECD_INSTALLER" ]]; then
    local confirm
    confirm=$(ask "Vamo instalar o $ECD_NAME? [S/n]")
    [[ "$confirm" =~ ^[Nn]$ ]] && ECD_INSTALLER=""
  elif [[ -n "$ECF_INSTALLER" ]]; then
    local confirm
    confirm=$(ask "Vamo instalar o $ECF_NAME? [S/n]")
    [[ "$confirm" =~ ^[Nn]$ ]] && ECF_INSTALLER=""
  fi

  if [[ -z "$ECD_INSTALLER" && -z "$ECF_INSTALLER" ]]; then
    echo
    info "Não selecionamos nada pra instalar, companheiro."
    exit 0
  fi
}

# ── Extração ──────────────────────────────────────────────────────────────────

# O instalador .sh da Receita é um SFX Install4j: [shell] [ZIP do app] [tar.gz runtime].
extract_app_zip() {
  local installer="$1" app_dir="$2"
  local payload total sfx_start zip_start

  payload=$(grep -a -m1 "^tail -c " "$installer" | awk '{print $3}' || true)
  [[ "$payload" =~ ^[0-9]+$ ]] \
    || fail "Esse instalador eu não reconheci, companheiro. Versões testadas: ECD 10.4.1, ECF 12.1.6."
  total=$(wc -c < "$installer" | xargs)
  sfx_start=$(( total - payload ))

  # Caminhos e offsets passados via argv com heredoc entre aspas (sem injeção/quebra
  # por caminhos com aspas, espaços ou caracteres especiais).
  zip_start=$(python3 - "$installer" "$sfx_start" << 'PYEOF'
import sys
installer, sfx_start = sys.argv[1], int(sys.argv[2])
with open(installer, 'rb') as f:
    data = f.read(sfx_start + 4)
print(data.find(b'PK\x03\x04'))
PYEOF
)
  [[ "$zip_start" =~ ^[0-9]+$ && "$zip_start" -ge 0 ]] \
    || fail "Não consegui achar os arquivos do programa em $(basename "$installer"), companheiro."

  step "Preparando os arquivos do programa..."
  python3 - "$installer" "$sfx_start" "$zip_start" "$app_dir" << 'PYEOF'
import sys, zipfile, io
installer, sfx_start, zip_start, app_dir = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
with open(installer, 'rb') as f:
    f.seek(zip_start)
    data = f.read(sfx_start - zip_start)
with zipfile.ZipFile(io.BytesIO(data)) as z:
    for member in z.namelist():
        if chr(92) not in member:  # ignora entradas com path no estilo Windows
            z.extract(member, app_dir)
PYEOF
  step_ok

  step "Preparando o runtime do instalador..."
  local tmp
  tmp=$(mktemp -d)
  tail -c "$payload" "$installer" | tar xz -C "$tmp"
  mkdir -p "$app_dir/.install4j"
  [[ -f "$tmp/i4jruntime.jar" ]] \
    || { rm -rf "$tmp"; fail "Não achei o runtime do instalador (i4jruntime.jar), companheiro — formato inesperado."; }
  cp "$tmp/i4jruntime.jar" "$app_dir/.install4j/"
  local launchers
  launchers=$(find "$tmp" -maxdepth 1 -name "launcher*.jar" | wc -l | xargs)
  [[ "$launchers" -ge 1 ]] \
    || { rm -rf "$tmp"; fail "Não achei o launcher do instalador, companheiro — formato inesperado."; }
  find "$tmp" -maxdepth 1 -name "launcher*.jar" -exec cp {} "$app_dir/.install4j/" \;
  rm -rf "$tmp"
  step_ok
}

# ── MySQL ─────────────────────────────────────────────────────────────────────

setup_mysql_dir() {
  local app_dir="$1"
  local mysql_dir="$app_dir/mysql"
  local bdemb_jar="$app_dir/lib/br.gov.serpro.bdembutido/bdembutido-mysql.jar"

  step "Arrumando o banco de dados..."
  mkdir -p "$mysql_dir/bin"

  # Estrutura share/data do MySQL vem dentro do bdembutido-mysql.jar
  ( cd "$mysql_dir" && jar xf "$bdemb_jar" mysql/estrutura.zip 2>/dev/null ) || true
  if [[ -f "$mysql_dir/mysql/estrutura.zip" ]]; then
    unzip -o -q "$mysql_dir/mysql/estrutura.zip" -d "$app_dir" 2>/dev/null || true
    rm -f "$mysql_dir/mysql/estrutura.zip"
  fi

  # Wrapper do mysqld: adapta flags do MySQL 5.x que o MariaDB 10.11 rejeita.
  # bind-address é REMOVIDO (não forçado para 127.0.0.1): em Macs gerenciados, o
  # firewall bloqueia o bind em 127.0.0.1 com "Operation not permitted" e o app
  # não inicia. Sem a flag, o MariaDB usa o default. A exposição é mitigada porque
  # a senha só é definida para root@127.0.0.1/localhost e não há root@'%' — nenhum
  # login remoto se autentica.
  cat > "$mysql_dir/bin/mysqld" << WRAPPER
#!/bin/bash
REAL_MYSQLD="$MARIADB_BIN/mysqld"
args=()
for arg in "\$@"; do
    case "\$arg" in
        --innodb_additional_mem_pool_size=*) ;;
        --query_cache_size=*)                ;;
        --myisam_max_extra_sort_file_size=*) ;;
        --bind-address=*)                    ;;
        --innodb_flush_method=normal)
            args+=("--innodb_flush_method=fsync") ;;
        --default-character-set=*)
            args+=("--character-set-server=\${arg#--default-character-set=}") ;;
        --default-collation=*)
            args+=("--collation-server=\${arg#--default-collation=}") ;;
        --table_cache=*)
            args+=("--table_open_cache=\${arg#--table_cache=}") ;;
        --max_heap_table_size=*MB)
            val="\${arg#--max_heap_table_size=}"
            args+=("--max_heap_table_size=\${val%MB}M") ;;
        *) args+=("\$arg") ;;
    esac
done
exec "\$REAL_MYSQLD" "\${args[@]}"
WRAPPER
  chmod +x "$mysql_dir/bin/mysqld"

  cat > "$mysql_dir/bin/mysqladmin" << ADMINWRAPPER
#!/bin/bash
exec "$MARIADB_BIN/mysqladmin" "\$@"
ADMINWRAPPER
  chmod +x "$mysql_dir/bin/mysqladmin"
  step_ok
}

# Lê a senha do banco diretamente da configuração embarcada no aplicativo
# (configuracoes/...conexao.configuracao dentro de *-infra-persistencia.jar).
# Assim, se a Receita mudar a senha numa versão futura, o script acompanha.
# Cai no fallback se não conseguir localizar/ler.
read_db_password() {
  local app_dir="$1" jar conf pw
  jar=$(find "$app_dir/lib" -name "*-infra-persistencia.jar" 2>/dev/null | head -1)
  if [[ -n "$jar" ]]; then
    conf=$(unzip -p "$jar" 'configuracoes/*conexao.configuracao' 2>/dev/null | LC_ALL=C tr -d '\r')
    pw=$(printf '%s' "$conf" | LC_ALL=C grep -ao 'CONFIGURACAO_SENHA=[^[:space:]]*' | head -1 | cut -d= -f2-)
  fi
  [[ -n "${pw:-}" ]] && printf '%s' "$pw" || printf '%s' "$DB_PASSWORD_FALLBACK"
}

init_database() {
  local app_dir="$1" db_password="$2"
  local data_dir="$app_dir/mysql/data"
  local log; log=$(mktemp)

  step "Inicializando o banco de dados..."
  rm -rf "$data_dir"
  mkdir -p "$data_dir"

  if ! "$MARIADB_BIN/mysql_install_db" \
        --auth-root-authentication-method=normal \
        --basedir="$(dirname "$MARIADB_BIN")" \
        --datadir="$data_dir" \
        --skip-test-db > "$log" 2>&1; then
    step_fail
    fail "Não consegui preparar o banco de dados, companheiro. Os detalhes tão em: $log"
  fi

  # Socket efêmero direto em /tmp. Nome aleatório (não previsível), caminho curto
  # (o limite de sockaddr_un é ~104 bytes). Não usamos um subdiretório temporário
  # porque, em Macs gerenciados, criar o socket dentro dele dispara EPERM no bind.
  # A janela é de poucos segundos e o banco está vazio nela, então o risco é baixo.
  local sock="/tmp/sped_${$}_${RANDOM}.sock"
  rm -f "$sock"
  "$MARIADB_BIN/mysqld" \
    --basedir="$(dirname "$MARIADB_BIN")" \
    --datadir="$data_dir" \
    --socket="$sock" \
    --skip-grant-tables \
    --skip-networking >> "$log" 2>&1 &
  local pid=$!

  local tries=0
  while [[ ! -S "$sock" && $tries -lt 30 ]]; do
    kill -0 "$pid" 2>/dev/null || break   # mysqld morreu — não adianta esperar
    sleep 1; tries=$(( tries + 1 ))
  done
  if [[ ! -S "$sock" ]]; then
    kill "$pid" 2>/dev/null || true
    rm -f "$sock"
    step_fail
    fail "O banco de dados não subiu, companheiro. Se o programa já tiver aberto, feche e tente de novo. Detalhes em: $log"
  fi

  # Define a senha em todas as contas root locais e remove usuários anônimos.
  "$MARIADB_BIN/mysql" --socket="$sock" 2>>"$log" << SQL || true
FLUSH PRIVILEGES;
ALTER USER IF EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '$db_password';
ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '$db_password';
ALTER USER IF EXISTS 'root'@'::1' IDENTIFIED BY '$db_password';
DELETE FROM mysql.global_priv WHERE User='';
FLUSH PRIVILEGES;
SQL

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$sock"
  rm -f "$log"
  step_ok
}

# ── Windows L&F stub (o ECF exige WindowsLookAndFeel, que não existe no macOS) ──

create_windows_laf_stub() {
  local app_dir="$1"
  local tmp stub_jar="$app_dir/.install4j/windows-laf-stub.jar"
  tmp=$(mktemp -d)

  mkdir -p "$tmp/com/sun/java/swing/plaf/windows"
  cat > "$tmp/com/sun/java/swing/plaf/windows/WindowsLookAndFeel.java" << 'JAVA'
package com.sun.java.swing.plaf.windows;
import javax.swing.plaf.metal.MetalLookAndFeel;
public class WindowsLookAndFeel extends MetalLookAndFeel {
    public String getName()        { return "Windows"; }
    public String getID()          { return "Windows"; }
    public String getDescription() { return "Windows Look and Feel (macOS stub)"; }
    public boolean isNativeLookAndFeel()    { return false; }
    public boolean isSupportedLookAndFeel() { return true;  }
}
JAVA

  javac "$tmp/com/sun/java/swing/plaf/windows/WindowsLookAndFeel.java" 2>/dev/null \
    || { rm -rf "$tmp"; fail "Não consegui preparar a peça de compatibilidade (javac), companheiro."; }
  jar cf "$stub_jar" -C "$tmp" com
  rm -rf "$tmp"
}

# ── Launcher ──────────────────────────────────────────────────────────────────

write_launcher() {
  local app_dir="$1" main_class="$2"
  cat > "$app_dir/launch.sh" << LAUNCH
#!/bin/bash
cd "\$(dirname "\$0")"
export JAVA_HOME="$DETECTED_JAVA_HOME"
[ -x "\$JAVA_HOME/bin/java" ] || export JAVA_HOME="\$(/usr/libexec/java_home 2>/dev/null)"
export PATH="\$JAVA_HOME/bin:\$PATH"
exec java \\
  -Dsun.java2d.dpiaware=true \\
  -Dsun.java2d.uiScale=1.0 \\
  -Dfile.encoding=ISO-8859-1 \\
  -XX:+UseParallelGC \\
  -Djava.net.preferIPv4Stack=true \\
  -server \\
  --add-exports=java.desktop/com.sun.java.swing.plaf.windows=ALL-UNNAMED \\
  --add-exports=java.security.jgss/sun.security.jgss=ALL-UNNAMED \\
  --add-opens=java.base/java.lang=ALL-UNNAMED \\
  --add-opens=java.base/java.lang.reflect=ALL-UNNAMED \\
  --add-opens=java.base/java.security=ALL-UNNAMED \\
  --add-opens=java.base/java.text=ALL-UNNAMED \\
  --add-opens=java.base/java.util=ALL-UNNAMED \\
  --add-opens=java.desktop/java.awt.font=ALL-UNNAMED \\
  --patch-module java.desktop=".install4j/windows-laf-stub.jar" \\
  -classpath ".install4j/*:./*" \\
  $main_class
LAUNCH
  chmod +x "$app_dir/launch.sh"
}

# Cria um .app. Retorna não-zero se não conseguir (ex.: /Applications sem permissão).
make_app_bundle() {
  local dest="$1" display_name="$2" app_dir="$3"
  local macos_dir="$dest/Contents/MacOS"
  local exe="$macos_dir/$display_name"
  local bundle_id
  bundle_id="br.gov.sped.$(basename "$app_dir" | tr '[:upper:]' '[:lower:]')"

  rm -rf "$dest" 2>/dev/null || true
  mkdir -p "$macos_dir" || return 1
  cat > "$dest/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$display_name</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>$display_name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict></plist>
PLIST
  cat > "$exe" << EXE
#!/bin/bash
exec "$app_dir/launch.sh"
EXE
  chmod +x "$exe"
  xattr -cr "$dest" 2>/dev/null || true
  [[ -x "$exe" ]]   # valor de retorno real da função
}

create_app_bundle() {
  local app_dir="$1" display_name="$2"

  step "Criando o atalho em /Applications..."
  if make_app_bundle "/Applications/$display_name.app" "$display_name" "$app_dir" 2>/dev/null; then
    step_ok
  else
    step_fail
    make_app_bundle "$HOME/Desktop/$display_name.app" "$display_name" "$app_dir" \
      || fail "Não consegui criar o atalho, companheiro. Mas o programa abre assim: $app_dir/launch.sh"
    info "Atalho criado na sua Área de Trabalho: $display_name.app"
    info "Pra ele aparecer no Launchpad, é só arrastar pra pasta de Aplicativos, companheiro."
  fi
}

# ── Instalação ────────────────────────────────────────────────────────────────

install_app() {
  local installer="$1" app_dir="$2" main_class="$3" name="$4" display_name="$5"

  echo
  section_header "$name"

  local data_backup=""
  if [[ -d "$app_dir" ]]; then
    local confirm
    confirm=$(ask "O $app_dir já existe, companheiro. Reinstalar? [s/N]")
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
      info "Tá certo, vou pular o $name."
      return
    fi
    # Preserva os dados, perguntando ao usuário (padrão: sim)
    if [[ -d "$app_dir/mysql/data" ]]; then
      local keep_data
      keep_data=$(ask "Quer manter os dados que já estão aí? [S/n]")
      if [[ ! "$keep_data" =~ ^[Nn]$ ]]; then
        data_backup=$(mktemp -d)
        cp -r "$app_dir/mysql/data" "$data_backup/"
        info "Seus dados estão guardados, pode ficar tranquilo."
      fi
    fi
  fi

  # Extrai num diretório temporário; só substitui o destino ao final.
  # data_backup é uma CÓPIA — o original em $app_dir permanece intacto até a troca.
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir' '${data_backup:-}'" EXIT

  extract_app_zip "$installer" "$tmp_dir"
  setup_mysql_dir "$tmp_dir"

  if [[ -n "$data_backup" ]]; then
    # Restaura os dados preservados (cópia — backup mantido até a troca concluir)
    rm -rf "$tmp_dir/mysql/data"
    cp -r "$data_backup/data" "$tmp_dir/mysql/data"
  else
    # Senha lida da configuração embarcada no app (com fallback)
    local db_password
    db_password=$(read_db_password "$tmp_dir")
    init_database "$tmp_dir" "$db_password"
  fi

  step "Criando stub de compatibilidade macOS..."
  create_windows_laf_stub "$tmp_dir"
  step_ok
  write_launcher "$tmp_dir" "$main_class"

  # Troca segura: move o antigo para o lado, instala o novo, só então apaga o antigo.
  mkdir -p "$(dirname "$app_dir")"
  local old_dir=""
  if [[ -d "$app_dir" ]]; then
    old_dir="${app_dir}.old.$$"
    rm -rf "$old_dir"
    mv "$app_dir" "$old_dir"
  fi
  if ! mv "$tmp_dir" "$app_dir"; then
    [[ -n "$old_dir" ]] && mv "$old_dir" "$app_dir" 2>/dev/null || true
    fail "Não consegui instalar em $app_dir, companheiro. Mas seus dados estão intactos."
  fi
  trap - EXIT
  [[ -n "$old_dir" ]] && rm -rf "$old_dir"
  [[ -n "$data_backup" ]] && rm -rf "$data_backup"

  create_app_bundle "$app_dir" "$display_name"

  INSTALLED+=("$name|$app_dir|$display_name")
  ok "$name instalado, companheiro"
}

# ── Resumo final ──────────────────────────────────────────────────────────────

print_summary() {
  [[ ${#INSTALLED[@]} -eq 0 ]] && return
  echo
  hr
  echo "  Tá feito, companheiro! A instalação foi concluída."
  echo
  for entry in "${INSTALLED[@]}"; do
    IFS='|' read -r name app_dir display_name <<< "$entry"
    local app_location
    if [[ -d "/Applications/$display_name.app" ]]; then
      app_location="Launchpad / Spotlight: $display_name"
    else
      app_location="Área de Trabalho: $display_name.app (arraste para a pasta de Aplicativos)"
    fi
    echo "  $name"
    echo "    • $app_location"
    echo "    • Terminal: $app_dir/launch.sh"
    echo
  done
  echo "  Ó: é só procurar o programa no Launchpad ou no Spotlight pelo nome aí em cima."
  echo "  Agora é trabalhar. Um abraço, e viva o povo brasileiro!"
  hr
}

# ── Preâmbulo ─────────────────────────────────────────────────────────────────

print_preamble() {
  echo
  hr
  echo "  Companheiros e companheiras,"
  echo
  echo "  Nunca antes na história deste país um contador pôde instalar o SPED no"
  echo "  seu Mac com tanta facilidade. Este script, fruto da luta e da determinação"
  echo "  do povo brasileiro, vai instalar o Sped Contábil (ECD) e o Sped ECF"
  echo "  direto no seu macOS — sem Wine, sem Windows, sem sofrimento."
  echo
  echo "  Mas antes de prosseguir, companheiro, é preciso que você vá até o site"
  echo "  da Receita Federal e baixe os instaladores na versão Linux:"
  echo
  echo "    ECD: $ECD_URL"
  echo "    ECF: $ECF_URL"
  echo
  echo "  Baixou? Tá na pasta Downloads? Então tá bom."
  echo
  hr
  echo
  echo "  Para continuar, companheiro, digite um L e pressione Enter."
  echo "  (De Lula. É claro.)"
  echo

  local input
  input=$(ask "")
  if [[ "$input" != "L" && "$input" != "l" ]]; then
    echo
    echo "  Sem o L não tem instalação, companheiro."
    echo
    exit 0
  fi
  hr
  echo
}

# ── Principal ─────────────────────────────────────────────────────────────────

print_preamble
ensure_prereqs
discover_installers

[[ -n "$ECD_INSTALLER" ]] && install_app "$ECD_INSTALLER" "$ECD_APP_DIR" "$ECD_MAIN_CLASS" "$ECD_NAME" "Sped Contábil"
[[ -n "$ECF_INSTALLER" ]] && install_app "$ECF_INSTALLER" "$ECF_APP_DIR" "$ECF_MAIN_CLASS" "$ECF_NAME" "Sped ECF"

print_summary
