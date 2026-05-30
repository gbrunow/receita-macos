# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single Bash script (`install.sh`) that installs the Brazilian Receita Federal SPED
programs — **Sped Contábil (ECD)** and **Sped ECF** — on macOS. These are officially
distributed only as Linux installers; this script makes them run natively on macOS
(Apple Silicon and Intel). There is no build system, no test suite, no dependencies to
vendor — the repo is the script plus `README.md` and `LICENSE`.

## Validation commands

```bash
bash -n install.sh        # syntax check
shellcheck install.sh     # lint
```

`shellcheck` reports exactly **four intentional** findings — do not "fix" them blindly:
- `SC2012` (ls in `find_in_dir`): intentional, `ls -t … | head -1 || true` for newest-by-mtime.
- `SC2015` x2 (`[[ ]] && ok || nok`): safe, `ok`/`nok` are `echo` and never fail.
- `SC2064` (double-quoted `trap`): intentional — `$tmp_dir`/`$data_backup` must expand at
  trap-set time, since locals are gone when EXIT fires.

Running the script itself (`bash install.sh` or the `curl … | bash` one-liner) is
**interactive and installs real software** (Homebrew/Java/MariaDB) — treat as destructive.

## Hard constraints (these have bitten us; respect them)

- **Target shell is macOS `/bin/bash` 3.2.** The `curl | bash` one-liner and the shebang
  resolve to it. Do not use bash 4+ features (associative arrays, `${var,,}`, `mapfile`, etc.).
- **`set -euo pipefail` is on.** A bare `VAR=$(cmd | pipe)` aborts the whole script if the
  pipe fails. This silently killed the installer-discovery recovery path before. Any
  command substitution that may "fail" needs `|| true` (see `find_in_dir`) or a guard.
- **Prompts must read from `/dev/tty`**, never stdin — stdin is the pipe under `curl | bash`.
  All prompting goes through `ask()`.
- **Live DB-launch testing is blocked inside the Apple Claude Code sandbox**: the sandbox
  returns `EPERM` ("Operation not permitted") on `mariadbd`'s socket bind, intermittently
  and then persistently after repeated launches. Per-function logic is verifiable from
  inside; a real end-to-end DB launch requires the sandbox to be lifted. Don't mistake the
  sandbox EPERM for a script bug.

## Architecture / flow

`install.sh` runs top-to-bottom at the bottom of the file:
`print_preamble → ensure_prereqs → discover_installers → install_app (per app) → print_summary`.

Key pieces:

- **The `.sh` installers are Install4j self-extracting archives** with three concatenated
  sections: `[shell script][app ZIP][gzipped-tar runtime]`. `extract_app_zip` parses this:
  the `^tail -c N` line in the stub gives the runtime payload size; the app ZIP sits between
  the shell text and the runtime, located by scanning for the `PK\x03\x04` magic. Offsets and
  paths are passed to `python3` via **argv with a quoted heredoc** (never interpolated into
  Python source — avoids injection and breakage on paths with quotes/spaces).

- **MariaDB compatibility shim.** The apps ship a 32-bit Linux `mysqld` and expect to spawn
  it at runtime. `setup_mysql_dir` replaces it with a wrapper script that forwards to
  Homebrew's `mariadb@10.11`, **stripping/translating MySQL 5.x flags** MariaDB 10.11 rejects
  (`innodb_additional_mem_pool_size`, `query_cache_size`, `default-character-set` →
  `character-set-server`, `table_cache` → `table_open_cache`, `innodb_flush_method=normal` →
  `fsync`, etc.). **`--bind-address` is stripped, NOT forced to `127.0.0.1`** — forcing
  loopback reintroduces an `Operation not permitted` bind failure on managed Macs. Exposure is
  mitigated because the root password is only set for `127.0.0.1`/`localhost`/`::1` and there
  is no wildcard `root@'%'`.

- **`init_database`** wipes/creates the data dir, runs `mysql_install_db`, starts a temporary
  `mysqld` on a short random `/tmp` socket with `--skip-networking --skip-grant-tables`, sets
  the DB password on all local root accounts, drops anonymous users, then stops it.

- **`read_db_password`** extracts the DB password from the app's own embedded config
  (`configuracoes/*conexao.configuracao` inside `*-infra-persistencia.jar`) so a future SPED
  version that changes it is picked up automatically. `DB_PASSWORD_FALLBACK` (`toor321`) is
  only used if that read fails. The config is latin-1, so `tr`/`grep` run under `LC_ALL=C`.

- **WindowsLookAndFeel stub.** ECF hard-requires `com.sun.java.swing.plaf.windows.WindowsLookAndFeel`,
  absent on macOS JDKs. `create_windows_laf_stub` compiles a `MetalLookAndFeel` subclass and the
  generated `launch.sh` injects it via `--patch-module java.desktop=…`.

- **`launch.sh` / `.app` bundle.** `write_launcher` pins `JAVA_HOME` to the install-time-validated
  17–22 JDK (so a later JDK 23+ install can't break the app). `make_app_bundle` creates a clickable
  `.app` in `/Applications`, falling back to `~/Desktop` when `/Applications` isn't writable
  (managed Macs). The `.app` filename/`CFBundleName` carry accents (`Sped Contábil`) but the
  `CFBundleIdentifier` is derived ASCII from the app dir name.

- **Reinstall is atomic and data-safe.** Everything is built in a temp dir; the old install is
  moved aside, the new one moved in, and only then the old removed. Preserved DB data is **copied**
  (not moved) so a failure never destroys the only copy. On reinstall the user is asked whether to
  keep existing data (`mysql/data` holds the user's escriturações).

## ECD vs ECF

They are the same flow parameterized by five constants each: glob, app dir, main class, name,
and bundle display name (`ECD_*` / `ECF_*` near the top). They differ only in those values plus
their DB port (3340 vs 3341) and the `*-infra-persistencia.jar` name — everything else is shared.

## Voice / copy convention (intentional, not a bug)

All user-facing output and the `README.md` are written in **Brazilian Portuguese, in the voice
of President Lula** (companheiro/companheira, warm, folksy) — this is a deliberate product choice,
including the "digite um L" gate in the preamble. When editing messages, keep the persona **but
preserve the actionable content** of errors (commands, file paths, log locations). Code comments
stay plain and technical.
