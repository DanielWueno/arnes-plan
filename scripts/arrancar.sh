#!/bin/bash
# ============================================================
# arrancar.sh — Deja el arnés listo en este proyecto, tanto si
#               es el primero que llega como si el ledger ya
#               existía. Es idempotente: correrlo dos veces no
#               hace daño.
# ============================================================
# Uso:
#   bash "$ARNES/arrancar.sh"           # detecta y hace lo que toque
#   bash "$ARNES/arrancar.sh" --donde docs/analisis-futuro
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

DONDE="docs/plan"
for a in "$@"; do
  case "$a" in
    --donde) shift; DONDE="${1:-docs/plan}" ;;
    --donde=*) DONDE="${a#*=}" ;;
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
EXISTENTE="$(python3 "$SCRIPT_DIR/ledger_path.py" 2>/dev/null || true)"

if [[ -n "$EXISTENTE" ]]; then
  echo -e "${GREEN}✓${NC} Este proyecto ya tiene un plan. ${BOLD}No se ha tocado nada.${NC}"
  echo -e "  ${CYAN}ledger${NC} $EXISTENTE"
  echo
  if python3 "$SCRIPT_DIR/validar-ledger.py" "$EXISTENTE"; then
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
  echo -e "  Cuando termines:  ${BOLD}python3 \"\$ARNES/validar-ledger.py\"${NC}"
fi

# ── El atajo, resuelto de verdad ────────────────────────────────────────────
# La ruta del plugin lleva la versión dentro y cambia en cada `plugin update`.
# Se imprime ya resuelta para que se pegue en el perfil del shell una vez y
# no haya que volver a buscarla nunca.
echo
echo -e "${DIM}────────────────────────────────────────────────────────────${NC}"
echo -e "Para no volver a buscar la ruta, añade esto a tu ${BOLD}~/.zshrc${NC} o ${BOLD}~/.bashrc${NC}:"
echo
echo "  export ARNES=\"\$(claude plugin list --json | python3 -c 'import json,sys; print(next(p[\"installPath\"] for p in json.load(sys.stdin) if p[\"id\"].startswith(\"arnes-plan\")))')/scripts\""
echo
echo -e "${DIM}  Se lo pregunta al CLI en vez de clavar la versión, así que sobrevive a${NC}"
echo -e "${DIM}  cada actualización. Hoy resuelve a: $SCRIPT_DIR${NC}"
