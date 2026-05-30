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

check_prereqs() {
  local java_ver brew_prefix

  command -v java >/dev/null 2>&1 \
    || fail "Java não encontrado. Instale com: brew install --cask temurin@21"

  # Versão "feature"; trata o esquema legado 1.x (1.8 → 8)
  java_ver=$(java -version 2>&1 | awk -F'"' '/version/ {print $2}')
  if [[ "$java_ver" == 1.* ]]; then
    java_ver=$(echo "$java_ver" | cut -d. -f2)
  else
    java_ver=$(echo "$java_ver" | cut -d. -f1)
  fi
  [[ "$java_ver" =~ ^[0-9]+$ ]] \
    || fail "Não foi possível detectar a versão do Java. Instale com: brew install --cask temurin@21"
  [[ "$java_ver" -ge 17 && "$java_ver" -le 22 ]] \
    || fail "É necessário Java 17 a 22 (versão encontrada: $java_ver). Instale com: brew install --cask temurin@21"

  command -v python3 >/dev/null 2>&1 \
    || fail "python3 não encontrado. Instale as Ferramentas de Linha de Comando com: xcode-select --install"

  command -v brew >/dev/null 2>&1 \
    || fail "Homebrew não encontrado. Instale em: https://brew.sh"
  brew_prefix=$(brew --prefix 2>/dev/null)

  MARIADB_BIN="$brew_prefix/opt/mariadb@10.11/bin"
  [[ -x "$MARIADB_BIN/mysqld" ]] \
    || fail "MariaDB 10.11 não encontrado. Instale com: brew install mariadb@10.11"

  # Fixa a JVM validada para o launcher (evita que um JDK 23+ instalado depois quebre o app)
  DETECTED_JAVA_HOME=$(/usr/libexec/java_home -v "$java_ver" 2>/dev/null || true)

  ok "Java $java_ver e MariaDB 10.11 prontos"
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
  input=$(ask "O instalador do $label está em outra pasta? Informe o caminho (ou Enter para pular):")
  [[ -z "$input" ]] && return 0
  resolved=$(resolve_path "$input" "$glob")
  if [[ -n "$resolved" ]]; then
    echo "$resolved"
  else
    echo "  ✗ Não encontrei o instalador do $label nessa pasta. Esse programa não será instalado." >&2
  fi
}

discover_installers() {
  local search_dir="${1:-$DEFAULT_SEARCH_DIR}"

  echo
  info "Procurando instaladores em $search_dir..."
  echo

  ECD_INSTALLER=$(find_in_dir "$search_dir" "$ECD_GLOB")
  ECF_INSTALLER=$(find_in_dir "$search_dir" "$ECF_GLOB")

  [[ -n "$ECD_INSTALLER" ]] && ok "ECD: $(basename "$ECD_INSTALLER")" || nok "ECD não encontrado"
  [[ -n "$ECF_INSTALLER" ]] && ok "ECF: $(basename "$ECF_INSTALLER")" || nok "ECF não encontrado"

  # Nada encontrado — pede outra pasta ou encerra
  if [[ -z "$ECD_INSTALLER" && -z "$ECF_INSTALLER" ]]; then
    echo
    info "Os instaladores devem ser baixados do site da Receita Federal (versão Linux):"
    info "  ECD: $ECD_URL"
    info "  ECF: $ECF_URL"
    echo
    local custom_dir
    custom_dir=$(ask "Em qual pasta estão os instaladores?")
    if [[ -z "$custom_dir" ]]; then
      echo
      info "Nenhum instalador selecionado. Baixe os arquivos e execute o script novamente."
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
    confirm=$(ask "Instalar os dois? [S/n]")
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
      local c_ecd c_ecf
      c_ecd=$(ask "Instalar o $ECD_NAME? [S/n]")
      [[ "$c_ecd" =~ ^[Nn]$ ]] && ECD_INSTALLER=""
      c_ecf=$(ask "Instalar o $ECF_NAME? [S/n]")
      [[ "$c_ecf" =~ ^[Nn]$ ]] && ECF_INSTALLER=""
    fi
  elif [[ -n "$ECD_INSTALLER" ]]; then
    local confirm
    confirm=$(ask "Instalar o $ECD_NAME? [S/n]")
    [[ "$confirm" =~ ^[Nn]$ ]] && ECD_INSTALLER=""
  elif [[ -n "$ECF_INSTALLER" ]]; then
    local confirm
    confirm=$(ask "Instalar o $ECF_NAME? [S/n]")
    [[ "$confirm" =~ ^[Nn]$ ]] && ECF_INSTALLER=""
  fi

  if [[ -z "$ECD_INSTALLER" && -z "$ECF_INSTALLER" ]]; then
    echo
    info "Nenhum instalador selecionado."
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
    || fail "Formato de instalador não reconhecido em $(basename "$installer"). Versões testadas: ECD 10.4.1, ECF 12.1.6."
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
    || fail "Não foi possível localizar os arquivos do aplicativo em $(basename "$installer")."

  step "Extraindo arquivos do aplicativo..."
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

  step "Extraindo runtime do instalador..."
  local tmp
  tmp=$(mktemp -d)
  tail -c "$payload" "$installer" | tar xz -C "$tmp"
  mkdir -p "$app_dir/.install4j"
  [[ -f "$tmp/i4jruntime.jar" ]] \
    || { rm -rf "$tmp"; fail "Runtime do instalador (i4jruntime.jar) não encontrado — formato inesperado."; }
  cp "$tmp/i4jruntime.jar" "$app_dir/.install4j/"
  local launchers
  launchers=$(find "$tmp" -maxdepth 1 -name "launcher*.jar" | wc -l | xargs)
  [[ "$launchers" -ge 1 ]] \
    || { rm -rf "$tmp"; fail "Launcher do instalador não encontrado — formato inesperado."; }
  find "$tmp" -maxdepth 1 -name "launcher*.jar" -exec cp {} "$app_dir/.install4j/" \;
  rm -rf "$tmp"
  step_ok
}

# ── MySQL ─────────────────────────────────────────────────────────────────────

setup_mysql_dir() {
  local app_dir="$1"
  local mysql_dir="$app_dir/mysql"
  local bdemb_jar="$app_dir/lib/br.gov.serpro.bdembutido/bdembutido-mysql.jar"

  step "Configurando diretório MySQL..."
  mkdir -p "$mysql_dir/bin"

  # Estrutura share/data do MySQL vem dentro do bdembutido-mysql.jar
  ( cd "$mysql_dir" && jar xf "$bdemb_jar" mysql/estrutura.zip 2>/dev/null ) || true
  if [[ -f "$mysql_dir/mysql/estrutura.zip" ]]; then
    unzip -o -q "$mysql_dir/mysql/estrutura.zip" -d "$app_dir" 2>/dev/null || true
    rm -f "$mysql_dir/mysql/estrutura.zip"
  fi

  # Wrapper do mysqld: adapta flags do MySQL 5.x que o MariaDB 10.11 rejeita.
  # bind-address é forçado para loopback (o app só precisa de 127.0.0.1; evita
  # expor o banco em todas as interfaces de rede).
  cat > "$mysql_dir/bin/mysqld" << WRAPPER
#!/bin/bash
REAL_MYSQLD="$MARIADB_BIN/mysqld"
args=()
for arg in "\$@"; do
    case "\$arg" in
        --innodb_additional_mem_pool_size=*) ;;
        --query_cache_size=*)                ;;
        --myisam_max_extra_sort_file_size=*) ;;
        --bind-address=*)
            args+=("--bind-address=127.0.0.1") ;;
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

  step "Inicializando banco de dados..."
  rm -rf "$data_dir"
  mkdir -p "$data_dir"

  if ! "$MARIADB_BIN/mysql_install_db" \
        --auth-root-authentication-method=normal \
        --basedir="$(dirname "$MARIADB_BIN")" \
        --datadir="$data_dir" \
        --skip-test-db > "$log" 2>&1; then
    step_fail
    fail "Falha ao inicializar o banco de dados. Detalhes em: $log"
  fi

  # Socket dentro de um diretório temporário 0700 (acesso restrito ao dono) e com
  # caminho curto (o limite de sockaddr_un é ~104 bytes).
  local sock_dir; sock_dir=$(mktemp -d /tmp/sped.XXXXXX)
  local sock="$sock_dir/mysqld.sock"
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
    rm -rf "$sock_dir"
    step_fail
    fail "O banco de dados não iniciou. Feche o programa caso já esteja aberto e tente novamente. Detalhes em: $log"
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
  rm -rf "$sock_dir"
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
    || { rm -rf "$tmp"; fail "Falha ao compilar o stub de compatibilidade (javac)."; }
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

  step "Criando atalho em /Applications..."
  if make_app_bundle "/Applications/$display_name.app" "$display_name" "$app_dir" 2>/dev/null; then
    step_ok
  else
    step_fail
    make_app_bundle "$HOME/Desktop/$display_name.app" "$display_name" "$app_dir" \
      || fail "Não foi possível criar o atalho. O programa ainda pode ser aberto por: $app_dir/launch.sh"
    info "Atalho criado na Área de Trabalho: $display_name.app"
    info "Para aparecer no Launchpad, arraste-o para a pasta de Aplicativos."
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
    confirm=$(ask "$app_dir já existe. Reinstalar? [s/N]")
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
      info "Pulando $name."
      return
    fi
    # Preserva os dados, perguntando ao usuário (padrão: sim)
    if [[ -d "$app_dir/mysql/data" ]]; then
      local keep_data
      keep_data=$(ask "Manter os dados existentes? [S/n]")
      if [[ ! "$keep_data" =~ ^[Nn]$ ]]; then
        data_backup=$(mktemp -d)
        cp -r "$app_dir/mysql/data" "$data_backup/"
        info "Dados preservados."
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
    fail "Falha ao instalar em $app_dir. Seus dados não foram alterados."
  fi
  trap - EXIT
  [[ -n "$old_dir" ]] && rm -rf "$old_dir"
  [[ -n "$data_backup" ]] && rm -rf "$data_backup"

  create_app_bundle "$app_dir" "$display_name"

  INSTALLED+=("$name|$app_dir|$display_name")
  ok "$name instalado"
}

# ── Resumo final ──────────────────────────────────────────────────────────────

print_summary() {
  [[ ${#INSTALLED[@]} -eq 0 ]] && return
  echo
  hr
  echo "  Instalação concluída!"
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
  echo "  Dica: procure o programa no Launchpad ou Spotlight pelo nome acima."
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
check_prereqs
discover_installers

[[ -n "$ECD_INSTALLER" ]] && install_app "$ECD_INSTALLER" "$ECD_APP_DIR" "$ECD_MAIN_CLASS" "$ECD_NAME" "Sped Contábil"
[[ -n "$ECF_INSTALLER" ]] && install_app "$ECF_INSTALLER" "$ECF_APP_DIR" "$ECF_MAIN_CLASS" "$ECF_NAME" "Sped ECF"

print_summary
