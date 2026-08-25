#!/bin/bash
# ============================================================
# arrancar.sh — Deja el arnés listo en este proyecto, tanto si
#               es el primero que llega como si el ledger ya
#               existía. Es idempotente: correrlo dos veces no
#               hace daño.
# ============================================================
# Uso:
#   /arnes-plan:plan-arrancar           # desde Claude Code: sin rutas
#   bash "$ARNES/arrancar.sh"           # o a mano, si ya tienes la ruta
#   bash "$ARNES/arrancar.sh" --donde docs/analisis-futuro
#   bash "$ARNES/arrancar.sh" --sin-atajo   # no instalar el comando `arnes`
#
# Por qué existe: el arranque documentado era `cp plantilla ledger.json`,
# y eso es una bomba. El segundo miembro del equipo clona el repositorio,
# sigue el README al pie de la letra, y le pasa el plan por encima al
# primero — sin preguntar, y sobre un JSON versionado que a esas alturas
# es la única fuente de verdad del avance.
#
# Un README que dice "ojo, si ya existe no lo copies" es la misma clase de
# regla que este proyecto lleva moviendo al código desde el principio: la
# que sólo se cumple si alguien se acuerda. Aquí la comprobación la hace
# la máquina, y NUNCA sobrescribe: si hay ledger, no se toca.
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=entorno.sh
source "$SCRIPT_DIR/entorno.sh"

DONDE="docs/plan"; ATAJO=1
for a in "$@"; do
  case "$a" in
    --donde) shift; DONDE="${1:-docs/plan}" ;;
    --donde=*) DONDE="${a#*=}" ;;
    --sin-atajo) ATAJO=0 ;;
    -h|--help) awk '/^# ={10,}$/{n++; if(n==2) exit} NR>1{sub(/^# ?/,""); print}' \
                   "${BASH_SOURCE[0]}"; exit 0 ;;
    *) ;;
  esac
done

# La raíz del proyecto que se trabaja, no la del plugin. Misma regla que
# plan-run.sh, y por el mismo motivo: instalado como plugin, el repositorio
# de este script es el DEL PLUGIN.
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  ROOT="$CLAUDE_PROJECT_DIR"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$ROOT"

echo
echo -e "${BOLD}Arnés de plan${NC} ${DIM}·${NC} $ROOT"
echo

# ── ¿Ya hay ledger? ─────────────────────────────────────────────────────────
# Se pregunta al mismo resolvedor que usa el resto del arnés, para que no
# haya dos ideas distintas de dónde vive el ledger.
EXISTENTE="$("$PY" "$SCRIPT_DIR/ledger_path.py" 2>/dev/null || true)"

if [[ -n "$EXISTENTE" ]]; then
  echo -e "${GREEN}✓${NC} Este proyecto ya tiene un plan. ${BOLD}No se ha tocado nada.${NC}"
  echo -e "  ${CYAN}ledger${NC} $EXISTENTE"
  echo
  if "$PY" "$SCRIPT_DIR/validar-ledger.py" "$EXISTENTE"; then
    :
  else
    echo -e "${YELLOW}⚠${NC}  El ledger tiene problemas, arriba están. No impiden trabajar,"
    echo -e "   pero conviene arreglarlos antes de que hagan elegir mal al arnés."
  fi
  echo
  echo -e "${BOLD}Estás listo.${NC} Lo siguiente que toca:"
  echo
  bash "$SCRIPT_DIR/plan-run.sh" --solo-anunciar 2>/dev/null || \
    echo -e "  ${DIM}(no hay ítems pendientes)${NC}"
else
  # ── No hay: se siembra. Aun así se comprueba el destino a mano, porque
  #    el resolvedor sólo mira las rutas convencionales y el usuario puede
  #    haber pedido otra con --donde.
  DESTINO="$DONDE/ejecucion-plan.estado.json"
  if [[ -e "$DESTINO" ]]; then
    echo -e "${RED}✗${NC} Ya existe ${BOLD}$DESTINO${NC} y no lo voy a sobrescribir."
    echo -e "${DIM}   Si de verdad quieres empezar de cero, muévelo tú primero.${NC}"
    exit 1
  fi
  mkdir -p "$DONDE"
  cp "$SCRIPT_DIR/../plantillas/ledger.plantilla.json" "$DESTINO"
  echo -e "${GREEN}✓${NC} Plan nuevo sembrado en ${BOLD}$DESTINO${NC}"
  echo
  echo -e "${BOLD}Ahora te toca a ti:${NC} escribe tus ítems. Es lo único que no se automatiza."
  echo -e "  ${DIM}Borra el ítem de ejemplo. Cada ítem necesita, como mínimo, un título que${NC}"
  echo -e "  ${DIM}diga QUÉ PASA HOY, una verificación que sea un comando, y un rollback.${NC}"
  echo -e "  ${DIM}Cambia también el campo _moneda: horas_maquina puede no ser tu recurso escaso.${NC}"
  echo
  echo -e "  Cuando termines:  ${BOLD}"$PY" \"\$ARNES/validar-ledger.py\"${NC}"
fi

# ── El atajo: un comando de verdad, no una variable ─────────────────────────
# Pedirle a alguien que resuelva una ruta y la meta en su perfil de shell es
# trabajo manual disfrazado de instalación, y encima caduca: la ruta lleva el
# número de versión dentro. Lo que se instala aquí es un lanzador de tres
# líneas que resuelve la instalación EN CADA EJECUCIÓN, así que sobrevive a
# todos los `claude plugin update` sin tocarlo nunca más.
#
# Va a ~/.local/bin porque es donde vive el propio `claude`: quien tenga Claude
# Code ya lo tiene en el PATH, así que no hay un segundo paso escondido.
[[ $ATAJO -eq 0 ]] && exit 0

BIN="$BIN_DIR"
ATAJO_RUTA="$BIN/arnes"
FIRMA="# arnes-plan:atajo"

echo
echo -e "${DIM}────────────────────────────────────────────────────────────${NC}"

if [[ -e "$ATAJO_RUTA" ]] && ! grep -q "$FIRMA" "$ATAJO_RUTA" 2>/dev/null; then
  # Hay un `arnes` que no pusimos nosotros. No se toca: sobrescribir un
  # ejecutable ajeno del PATH de alguien es exactamente lo que no debe hacer
  # un instalador.
  echo -e "${YELLOW}⚠${NC}  Ya hay un ${BOLD}arnes${NC} en $BIN que no es de este plugin. No lo toco."
  echo -e "${DIM}   Usa las rutas largas, o renombra el tuyo si quieres el atajo.${NC}"
  exit 0
fi

mkdir -p "$BIN"
cat > "$ATAJO_RUTA" <<'ATAJO_FIN'
#!/bin/bash
# arnes-plan:atajo — lanzador del arnés de plan.
# No clava ninguna ruta: resuelve la instalación en cada ejecución, así que
# sigue funcionando después de cada `claude plugin update`. Si lo borras, se
# vuelve a crear con `/arnes-plan:plan-arrancar`.
set -euo pipefail

# El intérprete se resuelve AQUÍ y no se hereda: este fichero se ejecuta solo,
# sin incluir el entorno del plugin. En Windows suele ser `python` y `python3`
# no existe.
if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python  >/dev/null 2>&1; then PY=python
else echo "arnes: no encuentro Python en el PATH." >&2; exit 127; fi

raiz_del_plugin() {
  local p
  # Lo autoritativo es el CLI. `claude plugin list` a secas NO da la ruta.
  p="$(claude plugin list --json 2>/dev/null \
       | "$PY" -c 'import json,sys
try: print(next(x["installPath"] for x in json.load(sys.stdin) if x["id"].startswith("arnes-plan")))
except Exception: pass' 2>/dev/null)" || true
  [[ -n "${p:-}" && -d "$p" ]] && { printf '%s' "$p"; return 0; }
  # Respaldo, por si `claude` no está en el PATH de este shell: el registro que
  # el propio CLI escribe. NO se elige la versión más alta del cache: ahí quedan
  # las instalaciones viejas y también versiones que nunca llegaron a activarse,
  # así que la más alta puede no ser la que está en uso — y correr en silencio
  # una versión que no es la instalada es exactamente el fallo que este arnés
  # existe para no cometer.
  p="$("$PY" -c 'import json, os, sys
r = os.path.expanduser("~/.claude/plugins/installed_plugins.json")
try:
    d = json.load(open(r, encoding="utf-8"))
except Exception:
    sys.exit(1)
for clave, entradas in d.get("plugins", {}).items():
    if clave.startswith("arnes-plan"):
        for e in entradas:
            if e.get("installPath"):
                print(e["installPath"]); sys.exit(0)
sys.exit(1)' 2>/dev/null)" || true
  [[ -n "${p:-}" && -d "$p" ]] && { printf '%s' "$p"; return 0; }
  return 1
}

DIR="$(raiz_del_plugin)" || {
  echo "arnes: no encuentro el plugin instalado." >&2
  echo "       Instálalo con: claude plugin install arnes-plan@arnes-plan" >&2
  exit 127
}

case "${1:-}" in
  # La ayuda vive en el plugin, no aquí: así se actualiza con él y este
  # lanzador sigue sin contener nada que pueda quedarse viejo. El respaldo
  # cubre el caso de un atajo más nuevo que el plugin instalado, que si no
  # contestaría con un error de bash en vez de con una ayuda.
  -h|--help|ayuda|help)
    if [[ -f "$DIR/scripts/ayuda.sh" ]]; then exec bash "$DIR/scripts/ayuda.sh"; fi
    exec bash "$DIR/scripts/plan-run.sh" --help ;;
  arrancar)  shift; exec bash "$DIR/scripts/arrancar.sh" "$@" ;;
  *)         exec bash "$DIR/scripts/plan-run.sh" "$@" ;;
esac
ATAJO_FIN
chmod +x "$ATAJO_RUTA"

# PowerShell y cmd no saben ejecutar un script de bash: necesitan un .cmd que
# se lo pase. En Unix este fichero no existe y no estorba.
if [[ $ES_WINDOWS -eq 1 ]]; then
  cat > "$BIN/arnes.cmd" <<'CMD_FIN'
@echo off
REM arnes-plan:atajo — envoltorio para PowerShell y cmd, que no ejecutan bash.
bash "%~dp0arnes" %*
CMD_FIN
  echo -e "${GREEN}✓${NC} Envoltorio ${BOLD}arnes.cmd${NC} escrito para PowerShell y cmd."
fi

echo -e "${GREEN}✓${NC} Atajo instalado. Desde cualquier proyecto, en la terminal:"
echo
echo -e "  ${BOLD}arnes${NC}                    el siguiente ítem, en sesión limpia"
echo -e "  ${BOLD}arnes --solo-anunciar${NC}    qué toca, sin ejecutar ni gastar"
echo -e "  ${BOLD}arnes 5.0 --auto${NC}         uno concreto, con menos prompts"
echo -e "  ${BOLD}arnes arrancar${NC}           esto mismo, en otro proyecto"
echo -e "  ${BOLD}arnes --help${NC}             todos los comandos, y dónde estás ahora"
echo

if ! command -v arnes >/dev/null 2>&1; then
  echo -e "${YELLOW}⚠${NC}  $BIN no está en tu PATH en esta terminal."
  # El consejo lo decide entorno.sh: en PowerShell un `export` no significa
  # nada, y darlo igual es peor que callarse — se sigue, no funciona, y parece
  # culpa de quien lo siguió.
  echo "     $CONSEJO_PATH"
  echo -e "${DIM}     (o abre una terminal nueva, si acabas de crearlo)${NC}"
fi
