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

# ── La codificación de la salida ────────────────────────────────────────────
# Por qué existe: en Windows, Python elige la codificación de `stdout` según a
# dónde escribe. A una consola escribe UTF-8; a una TUBERÍA cae al locale del
# sistema —cp1252 en un Windows en español—, donde `✓` no existe. El `print` de
# la línea de éxito lanzaba UnicodeEncodeError y el script salía 1, y los
# sitios donde el arnés CAPTURA la salida de un validador son justo los que
# deciden un veredicto: un ledger sano se anunciaba roto y un ítem bien cerrado
# quedaba "marcado hecho pero no lo demuestra".
#
# Esto cubre los `python -` de una línea incrustados en los .sh, que no tienen
# dónde ponerlo; cada script .py fija además la suya en su cabecera, que es lo
# que vale cuando se invocan a mano —la forma larga del README— o cuando los
# llama Claude Code, como al hook.
#
# Se pisa lo que traiga el entorno, y a propósito: la salida de estos Python no
# es texto para una persona, es el canal por el que se pasan datos entre los
# scripts del arnés —se captura con $(…) y se parte con sed—. Con otra
# codificación, un título con acento sale en bytes que no son UTF-8 y el `sed`
# de al lado contesta "illegal byte sequence": el ledger no tiene por qué caber
# en el locale de nadie.
export PYTHONIOENCODING=utf-8

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
     $usuario = [Environment]::GetEnvironmentVariable("Path", "User")
     [Environment]::SetEnvironmentVariable("Path", "$usuario;$HOME\.local\bin", "User")
     $env:Path += ";$HOME\.local\bin"   # y en la consola abierta'
else
  BIN_DIR="$HOME/.local/bin"
  CONSEJO_PATH='Añade a tu ~/.zshrc o ~/.bashrc:
     export PATH="$HOME/.local/bin:$PATH"'
fi

# ── Dejar la carpeta en el PATH sin trabajo manual ──────────────────────────
# En Windows, registrar una variable de entorno es editar el registro, y eso
# está fuera del dominio de quien sólo quería instalar un plugin: la última
# milla se convertía en tres líneas de PowerShell copiadas a mano. Se hace aquí.
#
# Siempre en el ámbito del USUARIO. El de máquina pide administrador y afecta a
# todas las cuentas, y en esa PATH no pinta nada un lanzador que vive en el
# perfil de una sola. Se lee ese mismo ámbito antes de escribirlo —`$env:Path`
# es la de máquina y la de usuario ya fundidas, y volcarla entera dejaría una
# copia permanente de las entradas del sistema— y no se añade si ya estaba.
#
# En Unix no hace nada: ~/.local/bin es donde vive el propio `claude`, así que
# ya está en el PATH de quien tiene Claude Code, y adivinar qué fichero de
# perfil se lee de verdad —zsh, bash, login o interactivo— falla en silencio.
# Devuelve 0 sólo si la PATH persistente quedó lista.
arnes_registrar_path() {
  local dir="$1" ps win
  [[ $ES_WINDOWS -eq 1 ]] || return 1
  ps="$(command -v powershell.exe || command -v pwsh.exe \
        || command -v powershell || command -v pwsh)" || return 1
  win="$(cygpath -w "$dir" 2>/dev/null || printf '%s' "$dir")"
  # La ruta viaja por el entorno y no dentro del texto del comando: un
  # nombre de usuario con una comilla no puede romper —ni ampliar— el script.
  ARNES_BIN_WIN="$win" "$ps" -NoProfile -NonInteractive -Command '
    $dir = $env:ARNES_BIN_WIN
    $u = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($u -split ";") -contains $dir) { exit 0 }
    $nuevo = if ([string]::IsNullOrEmpty($u)) { $dir } else { $u.TrimEnd(";") + ";" + $dir }
    [Environment]::SetEnvironmentVariable("Path", $nuevo, "User")
  ' >/dev/null 2>&1
}

# ── Una ruta del registro, dicha como la dice este shell ────────────────────
# Por qué existe: en Windows, `installed_plugins.json` guarda la ruta en forma
# nativa —`C:\Users\quien\.claude\plugins\cache\...`— y el `$(cd … && pwd)`
# con el que se compara contesta la forma POSIX de LA MISMA carpeta
# —`/c/Users/quien/...`—. Comparar las dos como cadenas no puede dar verdadero
# nunca, así que `doctor`, `--version` y `plan-run` denunciaban "esta NO es la
# copia instalada" en TODAS las instalaciones de Windows, correctas incluidas.
# Y de paso el barrido de copias viejas, que reconoce el cache por un glob
# `*/plugins/cache/*`, no llegaba ni a mirar: con backslashes ese patrón no
# encaja, así que `--limpiar` no tenía nunca nada que limpiar justo donde la
# acumulación es segura —una copia por `plugin update`—.
#
# Se pregunta al shell antes que a `cygpath`: `cd` + `pwd` devuelve la ruta con
# LA MISMA ortografía que usan los `$(cd … && pwd)` de los scripts, que es lo
# único que hace falta para que la comparación signifique algo. `cygpath` queda
# para la carpeta que ya no existe —una instalación borrada a mano—, donde `cd`
# no puede contestar.
#
# En Unix no toca nada: allí el registro y `pwd` ya hablan igual, y resolver de
# más cambiaría una ruta con symlinks por su destino a espaldas de quien la lee.
#
# Si nada sabe contestar, se devuelve la ruta tal cual: sin traducir dirá "no es
# la copia instalada", que es sólo un aviso; vacía, en cambio, se leería como
# "no hay plugin instalado", que es una respuesta distinta y falsa.
arnes_ruta_shell() {
  local p="$1" q
  [[ -n "$p" ]] || return 0
  if [[ $ES_WINDOWS -eq 1 ]]; then
    q="$(CDPATH='' cd -- "$p" 2>/dev/null && pwd)" || q=""
    [[ -n "$q" ]] && { printf '%s' "$q"; return 0; }
    q="$(cygpath -u "$p" 2>/dev/null)" || q=""
    [[ -n "$q" ]] && { printf '%s' "$q"; return 0; }
  fi
  printf '%s' "$p"
}

# ── Quién es la copia instalada ─────────────────────────────────────────────
# Lo dice el registro que escribe el propio CLI. Esta consulta estaba duplicada
# en plan-run.sh y en el lanzador de ~/.local/bin. El lanzador tiene que seguir
# con su copia —se ejecuta solo, sin incluir este fichero— pero dentro del
# plugin hay un solo dueño, y así `--version`, `doctor` y el aviso de "no es la
# copia instalada" no pueden contestar cosas distintas.
#
# Imprime  installPath<TAB>version<TAB>sha_corto  y nada si no está instalado.
# La ruta sale ya en la forma que entiende este shell (ver arnes_ruta_shell):
# quien la compara no tiene por qué saber en qué sistema corre.
arnes_registro() {
  local salida
  salida="$("$PY" - <<'PY' 2>/dev/null || true
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
)"
  [[ -n "$salida" ]] || return 0
  printf '%s\t%s\n' "$(arnes_ruta_shell "${salida%%$'\t'*}")" "${salida#*$'\t'}"
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
