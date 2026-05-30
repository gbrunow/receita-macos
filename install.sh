#!/bin/bash
# install.sh — Instala o SPED ECD e/ou ECF no macOS (Apple Silicon e Intel)
#
# Pré-requisitos:
#   - Java 17-22       brew install --cask temurin@21
#   - MariaDB 10.11    brew install mariadb@10.11
#
# Uso rápido:
#   curl -fsSL https://raw.githubusercontent.com/gbrunow/receita-macos/main/install.sh | bash

set -euo pipefail

# ── Constantes ────────────────────────────────────────────────────────────────

INSTALL_BASE="$HOME/ProgramasSPED"
DEFAULT_SEARCH_DIR="$HOME/Downloads"
DB_PASSWORD="toor321"

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

MARIADB_BIN=""          # set by check_prereqs
ECD_INSTALLER=""        # set by discover_installers
ECF_INSTALLER=""        # set by discover_installers
INSTALLED=()            # app dirs installed this run

# ── Saída ─────────────────────────────────────────────────────────────────────

ok()   { echo "  ✓ $*"; }
nok()  { echo "  ✗ $*"; }
info() { echo "  → $*"; }
fail() { echo; echo "  Erro: $*" >&2; exit 1; }
ask()  { read -r -p "  $* " reply < /dev/tty; echo "$reply"; }

# Print a step label aligned for a trailing ✓/✗
step()    { printf "  → %s" "$*"; }
step_ok() { printf "\033[80G✓\n"; }
step_fail() { printf "\033[80G✗\n"; }

# Pad a section header with trailing ─ to fill 80 visible columns
section_header() {
  local line="  ── $* ──"
  local chars
  chars=$(printf '%s' "$line" | wc -m | xargs)
  printf '%s' "$line"
  local fill=$(( 80 - chars ))
  [[ $fill -gt 0 ]] && printf '─%.0s' $(seq 1 $fill)
  echo
}

# ── Pré-requisitos ────────────────────────────────────────────────────────────

check_prereqs() {
  local java_ver brew_prefix

  java_ver=$(java -version 2>&1 | awk -F'"' '/version/ {print $2}' | cut -d. -f1)
  [[ "$java_ver" -ge 17 && "$java_ver" -le 22 ]] \
    || fail "Java 17-22 necessário (encontrado: $java_ver). Instale com: brew install --cask temurin@21"

  brew_prefix=$(brew --prefix 2>/dev/null) \
    || fail "Homebrew não encontrado. Instale em: https://brew.sh"

  MARIADB_BIN="$brew_prefix/opt/mariadb@10.11/bin"
  [[ -x "$MARIADB_BIN/mysqld" ]] \
    || fail "MariaDB 10.11 não encontrado. Instale com: brew install mariadb@10.11"

  ok "Java $java_ver e MariaDB 10.11 prontos"
}

# ── Descoberta de instaladores ────────────────────────────────────────────────

find_in_dir() {
  local dir="$1" glob="$2"
  # shellcheck disable=SC2086
  ls -t "$dir"/$glob 2>/dev/null | head -1
}

resolve_path() {
  local input="$1" glob="$2"
  input="${input/#\~/$HOME}"
  if   [[ -f "$input" ]]; then echo "$input"
  elif [[ -d "$input" ]]; then find_in_dir "$input" "$glob"
  fi
}

ask_custom_path() {
  local label="$1" glob="$2"
  local input resolved
  input=$(ask "O instalador do $label está em outra pasta? Informe o caminho (ou Enter para pular):")
  [[ -z "$input" ]] && return 0
  resolved=$(resolve_path "$input" "$glob")
  if [[ -n "$resolved" ]]; then
    echo "$resolved"
  else
    nok "Nenhum instalador $label encontrado em $input — pulando."
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
    discover_installers "$custom_dir"
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

extract_app_zip() {
  local installer="$1" app_dir="$2"
  local payload total sfx_start zip_start

  payload=$(grep -a -m1 "^tail -c " "$installer" | awk '{print $3}')
  total=$(wc -c < "$installer" | xargs)
  sfx_start=$(( total - payload ))

  zip_start=$(python3 -c "
with open('$installer','rb') as f:
    data = f.read($sfx_start + 4)
print(data.find(b'PK\x03\x04'))
")
  [[ "$zip_start" -gt 0 ]] || fail "Não foi possível localizar os arquivos em $installer"

  step "Extraindo arquivos do aplicativo..."
  python3 - << PYEOF
with open('$installer','rb') as f:
    f.seek($zip_start)
    data = f.read($sfx_start - $zip_start)
import zipfile, io
with zipfile.ZipFile(io.BytesIO(data)) as z:
    for member in z.namelist():
        if chr(92) not in member:
            z.extract(member, '$app_dir')
PYEOF
  step_ok

  step "Extraindo runtime do instalador..."
  local tmp
  tmp=$(mktemp -d)
  tail -c "$payload" "$installer" | tar xz -C "$tmp"
  mkdir -p "$app_dir/.install4j"
  cp "$tmp/i4jruntime.jar" "$app_dir/.install4j/"
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

  # Extract mysql share/data structure — run in subshell to isolate the cd
  ( cd "$mysql_dir" && jar xf "$bdemb_jar" mysql/estrutura.zip 2>/dev/null ) || true
  if [[ -f "$mysql_dir/mysql/estrutura.zip" ]]; then
    unzip -o -q "$mysql_dir/mysql/estrutura.zip" -d "$app_dir" 2>/dev/null || true
    rm -f "$mysql_dir/mysql/estrutura.zip"
  fi

  # mysqld wrapper — strips flags removed in MariaDB 10.11
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

init_database() {
  local app_dir="$1"
  local data_dir="$app_dir/mysql/data"

  step "Inicializando banco de dados..."
  rm -rf "$data_dir"
  mkdir -p "$data_dir"

  "$MARIADB_BIN/mysql_install_db" \
    --auth-root-authentication-method=normal \
    --basedir="$(dirname "$MARIADB_BIN")" \
    --datadir="$data_dir" \
    --skip-test-db \
    > /dev/null 2>&1

  local sock="/tmp/sped_install_$$.sock"
  "$MARIADB_BIN/mysqld" \
    --basedir="$(dirname "$MARIADB_BIN")" \
    --datadir="$data_dir" \
    --socket="$sock" \
    --skip-grant-tables \
    --skip-networking \
    2>/dev/null &
  local pid=$!

  local tries=0
  while [[ ! -S "$sock" && $tries -lt 15 ]]; do sleep 1; tries=$(( tries + 1 )); done
  if [[ ! -S "$sock" ]]; then
    kill "$pid" 2>/dev/null || true
    fail "MariaDB não iniciou durante a configuração"
  fi

  "$MARIADB_BIN/mysql" --socket="$sock" -e \
    "FLUSH PRIVILEGES;
     ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
     FLUSH PRIVILEGES;" 2>/dev/null

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$sock"
  step_ok
}

# ── Windows L&F stub (ECF needs WindowsLookAndFeel which doesn't exist on macOS) ─

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

  javac "$tmp/com/sun/java/swing/plaf/windows/WindowsLookAndFeel.java" 2>/dev/null
  jar cf "$stub_jar" -C "$tmp" com
  rm -rf "$tmp"
}

# ── Launcher ──────────────────────────────────────────────────────────────────

write_launcher() {
  local app_dir="$1" main_class="$2"
  cat > "$app_dir/launch.sh" << LAUNCH
#!/bin/bash
cd "\$(dirname "\$0")"
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

make_app_bundle() {
  local dest="$1" bundle_name="$2" app_dir="$3"
  local macos_dir="$dest/Contents/MacOS"
  local exe="$macos_dir/$bundle_name"
  rm -rf "$dest"
  mkdir -p "$macos_dir"
  cat > "$dest/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$bundle_name</string>
  <key>CFBundleIdentifier</key><string>br.gov.sped.$(echo "$bundle_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '.')</string>
  <key>CFBundleName</key><string>$bundle_name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict></plist>
PLIST
  cat > "$exe" << EXE
#!/bin/bash
export JAVA_HOME=\$(/usr/libexec/java_home 2>/dev/null)
export PATH="\$JAVA_HOME/bin:\$PATH"
exec "$app_dir/launch.sh"
EXE
  chmod +x "$exe"
  xattr -cr "$dest" 2>/dev/null || true
}

create_app_bundle() {
  local app_dir="$1" bundle_name="$2"

  step "Criando atalho em /Applications..."
  if make_app_bundle "/Applications/$bundle_name.app" "$bundle_name" "$app_dir" 2>/dev/null; then
    step_ok
  else
    step_fail
    local desktop_bundle="$HOME/Desktop/$bundle_name.app"
    make_app_bundle "$desktop_bundle" "$bundle_name" "$app_dir"
    info "Atalho criado na Área de Trabalho: $bundle_name.app"
    info "Para aparecer no Launchpad, arraste-o para a pasta de Aplicativos."
  fi
}

# ── Instalação ────────────────────────────────────────────────────────────────

install_app() {
  local installer="$1" app_dir="$2" main_class="$3" name="$4" bundle_name="$5"

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
    # Ask about data preservation, defaulting to yes
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

  # Extract to temp dir first; move into place only on success
  local tmp_dir
  tmp_dir=$(mktemp -d)
  trap "rm -rf '$tmp_dir' '${data_backup:-}'" EXIT

  extract_app_zip "$installer" "$tmp_dir"
  setup_mysql_dir "$tmp_dir"

  if [[ -n "$data_backup" ]]; then
    # Restore preserved data — skip fresh db init
    rm -rf "$tmp_dir/mysql/data"
    mv "$data_backup/data" "$tmp_dir/mysql/data"
    data_backup=""
  else
    init_database "$tmp_dir"
  fi

  step "Criando stub de compatibilidade macOS..."
  create_windows_laf_stub "$tmp_dir"
  step_ok
  write_launcher  "$tmp_dir" "$main_class"

  rm -rf "$app_dir"
  mkdir -p "$(dirname "$app_dir")"
  mv "$tmp_dir" "$app_dir"
  trap - EXIT

  create_app_bundle "$app_dir" "$bundle_name"

  INSTALLED+=("$name|$app_dir|$bundle_name")
  ok "$name instalado"
}

# ── Resumo final ──────────────────────────────────────────────────────────────

print_summary() {
  [[ ${#INSTALLED[@]} -eq 0 ]] && return
  echo
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Instalação concluída!"
  echo
  for entry in "${INSTALLED[@]}"; do
    IFS='|' read -r name app_dir bundle_name <<< "$entry"
    local app_location
    if [[ -d "/Applications/$bundle_name.app" ]]; then
      app_location="Launchpad / Spotlight: $bundle_name"
    else
      app_location="Área de Trabalho: $bundle_name.app (arraste para a pasta de Aplicativos para aparecer no Launchpad)"
    fi
    echo "  $name"
    echo "    • $app_location"
    echo "    • Terminal: $app_dir/launch.sh"
    echo
  done
  echo "  Dica: procure o programa no Launchpad ou Spotlight"
  echo "  pelo nome acima, ou clique duas vezes em /Applications."
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Preamble ──────────────────────────────────────────────────────────────────

print_preamble() {
  echo
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
}

# ── Principal ─────────────────────────────────────────────────────────────────

print_preamble
check_prereqs
discover_installers

[[ -n "$ECD_INSTALLER" ]] && install_app "$ECD_INSTALLER" "$ECD_APP_DIR" "$ECD_MAIN_CLASS" "$ECD_NAME" "Sped Contabil"
[[ -n "$ECF_INSTALLER" ]] && install_app "$ECF_INSTALLER" "$ECF_APP_DIR" "$ECF_MAIN_CLASS" "$ECF_NAME" "Sped ECF"

print_summary
