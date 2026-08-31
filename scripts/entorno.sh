# -*- sh -*-
# Se incluye con `source`, no se ejecuta. Resuelve lo que cambia entre sistemas,
# para que ningún script tenga que saberlo por su cuenta.
#
# Por qué existe: el arnés se escribió en un macOS y lo daba por supuesto. Un
# compañero lo instaló en Windows/PowerShell y el núcleo funcionó —el ledger se
# sembró— pero la última milla le dio instrucciones falsas: `~/.local/bin`,
# `export PATH=...` y `python3`, ninguna de las tres válida ahí. Un consejo
# equivocado es peor que ninguno: se sigue, no funciona, y parece culpa de quien
# lo sigue.

# ── El intérprete ───────────────────────────────────────────────────────────
# En Windows el ejecutable suele llamarse `python` y `python3` no existe; en
# muchos Linux es al revés. Se resuelve una vez y se usa "$PY" en todas partes.
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python  >/dev/null 2>&1; then PY=python
else PY=python3; fi   # Que falle con un mensaje claro y no con "PY: not found".

# ── El sistema ──────────────────────────────────────────────────────────────
# $OSTYPE lo pone bash: en Windows el arnés corre sobre git-bash o WSL, que se
# identifican como msys/cygwin. Se prefiere a `uname` por no depender de otro
# binario más.
case "${OSTYPE:-}" in
  msys*|cygwin*|win32*) ES_WINDOWS=1 ;;
  *)                    ES_WINDOWS=0 ;;
esac

# ── Dónde va el lanzador, y cómo se pone en el PATH ─────────────────────────
# En Unix, ~/.local/bin: es donde vive el propio `claude`, así que ya está en el
# PATH de quien tiene Claude Code. En Windows esa carpeta existe pero PowerShell
# no la mira, y además no sabe ejecutar un script de bash — por eso allí se
# escribe también un .cmd que se lo pasa a bash.
if [[ $ES_WINDOWS -eq 1 ]]; then
  BIN_DIR="$HOME/.local/bin"
  CONSEJO_PATH='En PowerShell, para dejarlo permanente:
     $env:Path += ";$HOME\.local\bin"
     [Environment]::SetEnvironmentVariable("Path", $env:Path, "User")'
else
  BIN_DIR="$HOME/.local/bin"
  CONSEJO_PATH='Añade a tu ~/.zshrc o ~/.bashrc:
     export PATH="$HOME/.local/bin:$PATH"'
fi

# ── Quién es la copia instalada ─────────────────────────────────────────────
# Lo dice el registro que escribe el propio CLI. Esta consulta estaba duplicada
# en plan-run.sh y en el lanzador de ~/.local/bin. El lanzador tiene que seguir
# con su copia —se ejecuta solo, sin incluir este fichero— pero dentro del
# plugin hay un solo dueño, y así `--version`, `doctor` y el aviso de "no es la
# copia instalada" no pueden contestar cosas distintas.
#
# Imprime  installPath<TAB>version<TAB>sha_corto  y nada si no está instalado.
arnes_registro() {
  "$PY" - <<'PY' 2>/dev/null || true
import json, os, sys
r = os.path.expanduser("~/.claude/plugins/installed_plugins.json")
try:
    d = json.load(open(r, encoding="utf-8"))
except Exception:
    sys.exit(0)
for clave, entradas in d.get("plugins", {}).items():
    if clave.startswith("arnes-plan"):
        for e in entradas:
            if e.get("installPath"):
                print("\t".join((e["installPath"], e.get("version") or "",
                                 (e.get("gitCommitSha") or "")[:7])))
                sys.exit(0)
PY
}

# ── La versión del código que se está ejecutando ────────────────────────────
# La del manifiesto que está AL LADO de los scripts que corren, que no siempre
# es la registrada como instalada: correr una copia del cache a propósito es
# legítimo, y en ese caso la respuesta honesta es la de la copia. Recibe el
# directorio de scripts.
arnes_version_plugin() {
  "$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
      "$1/../.claude-plugin/plugin.json" 2>/dev/null || echo '?'
}

# ── El sha del código que se está ejecutando ────────────────────────────────
# Se prefiere git a lo que diga el registro: el registro anota el commit del
# clon del marketplace EN EL MOMENTO DE INSTALAR, así que sobre una copia
# editada a mano —o sobre el propio clon de desarrollo, donde `main` ya avanzó—
# mentiría. Sobre la copia instalada no hay `.git` y entonces sí manda el
# registro. Si no se puede saber, no se inventa: se calla.
#
# El toplevel tiene que traer el manifiesto del plugin. Sin esa comprobación,
# un arnés vendorizado dentro de otro proyecto contestaría el commit DE ESE
# proyecto, que es un sha real y de otra cosa: la peor clase de respuesta.
arnes_sha_git() {
  local raiz top
  raiz="$1"
  top="$(git -C "$raiz" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -f "$top/.claude-plugin/plugin.json" ]] || return 1
  local sha
  sha="$(git -C "$raiz" rev-parse --short HEAD 2>/dev/null)" || return 1
  [[ -n "$(git -C "$raiz" status --porcelain 2>/dev/null)" ]] && sha="$sha-sucio"
  printf '%s' "$sha"
}
