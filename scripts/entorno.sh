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
