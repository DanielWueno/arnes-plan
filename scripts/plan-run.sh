#!/bin/bash
# ============================================================
# plan-run.sh — Ejecuta UN ítem del ledger en una sesión de
#               contexto limpio, anunciándolo antes.
# ============================================================
# Uso (ARNES = el directorio de este script; instalado como plugin sale de
# `claude plugin list`, y dentro de una sesión es ${CLAUDE_PLUGIN_ROOT}/scripts):
#   bash "$ARNES/plan-run.sh"              # el siguiente pendiente
#   bash "$ARNES/plan-run.sh" 5.0          # un ítem concreto
#   bash "$ARNES/plan-run.sh" ola:5        # el siguiente de la Ola 5
#   bash "$ARNES/plan-run.sh" 5.0 --solo-anunciar    # sólo la ficha, no ejecuta
#   bash "$ARNES/plan-run.sh" 5.0 --auto             # menos prompts de permisos
#   bash "$ARNES/plan-run.sh" 4.6 --desatendido      # sin nadie delante (con guardas)
#
# Modos de permisos:
#   (por defecto)   interactivo. Apruebas lo que pida. Es lo correcto casi siempre.
#   --auto          interactivo, pero con el clasificador de auto mode decidiendo
#                   los permisos rutinarios. Sigue frenando lo destructivo y sigue
#                   habiendo alguien para confirmar una corrida larga.
#   --desatendido   sin sesión interactiva (claude -p). Para los ítems mecánicos.
#                   Se NIEGA si el ítem pide más de 1 hora de máquina, si lleva
#                   multiagente o si está bloqueado: en modo -p no hay a quién
#                   preguntar, y el protocolo exige preguntar en esos casos.
#                   --igual salta esas guardas bajo tu responsabilidad, y
#                   también la comprobación de que la ficha esté completa.
#                   Acepta un techo de gasto: --desatendido=3  (dólares, def. 5)
#
# Puertas de cierre (todas las modalidades, tras salir la sesión):
#   Un ítem que vuelve marcado `hecho` lo marcó el mismo agente que lo hizo:
#   por sí solo es autoevaluación. Al cerrar se comprueban dos cosas que no
#   dependen de su palabra:
#     · que dejó `resultado` escrito — qué se hizo y qué lo prueba;
#     · que `verificacion_comando`, si la ficha lo trae, sale 0 corriéndolo
#       AQUÍ, no en la sesión que lo declaró hecho.
#   Si alguna falla, el script sale distinto de 0 y lo dice. No revierte nada:
#   el commit ya existe y deshacerlo es decisión tuya, con el `rollback` de la
#   ficha delante. `--igual` salta las dos.
#   El comando tiene un límite de tiempo: ARNES_LIMITE_VERIFICACION (def. 900 s).
#
# Por qué existe: /plan-siguiente delega la ejecución a un
# subagente, así que ESA parte ya corre en contexto limpio, pero
# el hilo principal acumula contexto entre invocaciones. Aquí
# cada ítem arranca un proceso `claude` nuevo: contexto limpio de
# verdad, con nombre de sesión propio, y el modelo y el esfuerzo
# tomados del ledger en vez de escritos a mano.
#
# El anuncio previo NO cuesta tokens: sale del ledger con python.
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Raíz del proyecto SOBRE EL QUE SE TRABAJA. No se deriva de dónde vive este
# script, y la distinción es la que hace que el arnés funcione instalado:
# cuando llega como plugin, $SCRIPT_DIR está en ~/.claude/plugins/..., cuyo
# repositorio git es el DEL PLUGIN. Derivar la raíz de ahí —como hacía la
# versión vendorizada, que podía permitírselo porque vivía dentro del propio
# proyecto— haría que `git status`, las guardas de árbol sucio y el commit de
# cierre apuntaran al repositorio equivocado, y en silencio.
#
# Orden: lo que diga Claude Code, si no la raíz del repo desde el que se
# invoca, si no el directorio actual.
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  ROOT="$CLAUDE_PROJECT_DIR"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
LEDGER="$(cd "$ROOT" && python3 "$SCRIPT_DIR/ledger_path.py" 2>/dev/null || true)"

# Las banderas se aceptan en cualquier posición: el primer argumento que no
# empiece por "--" es el id o el ola:N.
ARG=""; SOLO_ANUNCIAR=0; MODO="interactivo"; PRESUPUESTO=5; FORZAR=0
for a in "$@"; do
  case "$a" in
    --solo-anunciar|--anunciar) SOLO_ANUNCIAR=1 ;;
    --auto)                     MODO="auto" ;;
    --desatendido)              MODO="desatendido" ;;
    --desatendido=*)            MODO="desatendido"; PRESUPUESTO="${a#*=}" ;;
    --igual|--force)            FORZAR=1 ;;
    -h|--help)                  awk '/^# ={10,}$/{n++; if(n==3) exit} NR>1{sub(/^# ?/,""); print}' \
                                    "${BASH_SOURCE[0]}"; exit 0 ;;
    --*) echo "Bandera desconocida: $a (usa --help)"; exit 1 ;;
    *)   [[ -z "$ARG" ]] && ARG="$a" || { echo "Sobra el argumento: $a"; exit 1; } ;;
  esac
done

command -v claude >/dev/null || { echo -e "${RED}✗${NC} 'claude' no está en el PATH."; exit 1; }
if [[ -z "$LEDGER" || ! -f "$LEDGER" ]]; then
  echo -e "${RED}✗${NC} No encuentro el ledger."
  echo "   Se buscó en las rutas convencionales bajo $ROOT."
  echo "   Crea uno con:  cp $SCRIPT_DIR/../plantillas/ledger.plantilla.json docs/plan/ejecucion-plan.estado.json"
  echo "   o apunta a él: export PLAN_LEDGER=/ruta/al/ejecucion-plan.estado.json"
  echo "   Guía completa: $SCRIPT_DIR/../README.md"
  exit 1
fi

# ── Resolver el ítem desde el ledger (coste: cero tokens) ────────────────────
FICHA="$(python3 - "$LEDGER" "$ARG" <<'PY'
import json, sys
ledger, arg = sys.argv[1], sys.argv[2]
d = json.load(open(ledger))
ola_filtro = int(arg.split(':', 1)[1]) if arg.startswith('ola:') else None
id_pedido  = arg if arg and not arg.startswith('ola:') else None

elegido = ola_elegida = None
for o in d['olas']:
    if ola_filtro is not None and o['ola'] != ola_filtro:
        continue
    for it in o['items']:
        if id_pedido:
            if it['id'].startswith(id_pedido):
                elegido, ola_elegida = it, o
                break
        elif it['estado'] in ('pendiente', 'en_curso'):
            elegido, ola_elegida = it, o
            break
    if elegido:
        break

if not elegido:
    print('ERROR\tNo hay ítem que encaje con: ' + (arg or '(siguiente pendiente)'))
    raise SystemExit(0)

campos = {
    'id': elegido['id'],
    'titulo': ' '.join(elegido['titulo'].split()),
    'modelo': elegido['modelo'],
    'esfuerzo': elegido['esfuerzo'],
    'horas': str(elegido['horas_maquina']),
    'estado': elegido['estado'],
    'multiagente': 'sí' if elegido['multiagente'] else 'no',
    'ola': str(ola_elegida['ola']),
    'ola_nombre': ola_elegida['nombre'],
    'verificacion': ' '.join(elegido['verificacion'].split()),
    'bloquea': ' '.join(elegido.get('bloquea', '').split()),
    'bloqueado_por': ' '.join(elegido.get('bloqueado_por', '').split()),
    'aviso_item': ' '.join(elegido.get('advertencia_de_coste', '').split()),
    'aviso_ola': ' '.join(ola_elegida.get('advertencia_de_coste', '').split()),
    'verif_cmd': ' '.join((elegido.get('verificacion_comando') or '').split()),
}
for k, v in campos.items():
    print(k + '\t' + v)
PY
)"

if grep -q '^ERROR' <<<"$FICHA"; then
  echo -e "${RED}✗${NC} $(sed -n 's/^ERROR\t//p' <<<"$FICHA")"; exit 1
fi
campo() { sed -n "s/^$1\t//p" <<<"$FICHA"; }

ID=$(campo id);         TITULO=$(campo titulo);   MODELO=$(campo modelo)
ESFUERZO=$(campo esfuerzo); HORAS=$(campo horas);  ESTADO=$(campo estado)
MULTI=$(campo multiagente); OLA=$(campo ola);      OLA_NOMBRE=$(campo ola_nombre)
VERIF=$(campo verificacion); BLOQUEA=$(campo bloquea)
BLOQ_POR=$(campo bloqueado_por); AVISO_I=$(campo aviso_item); AVISO_O=$(campo aviso_ola)
VERIF_CMD=$(campo verif_cmd)

# ── Anuncio ─────────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}  Ola $OLA — $OLA_NOMBRE${NC}"
echo -e "${BOLD}  $ID${NC}"
echo -e "${BOLD}────────────────────────────────────────────────────────────${NC}"
echo -e "  $TITULO"
echo
# Etiquetas ya alineadas a mano: printf cuenta BYTES, no caracteres, así que
# un %-12s desalinea en cuanto la etiqueta lleva un acento.
echo -e "  ${CYAN}modelo     ${NC} $MODELO / esfuerzo $ESFUERZO"
echo -e "  ${CYAN}máquina    ${NC} $HORAS h"
echo -e "  ${CYAN}multiagente${NC} $MULTI"
echo -e "  ${CYAN}estado     ${NC} $ESTADO"
echo
echo -e "  ${DIM}verificación:${NC} $VERIF" | fold -s -w 76 | sed '2,$s/^/               /'
# Si la ficha trae comando, se enseña ahora: es el criterio con el que se le va
# a medir al cerrar, y verlo antes es lo que evita discutirlo después.
[[ -n "$VERIF_CMD" ]] && echo -e "  ${DIM}al cerrar:   ${NC} ${BOLD}$VERIF_CMD${NC}"
[[ -n "$BLOQ_POR" ]] && { echo; echo -e "  ${RED}BLOQUEADO POR:${NC} $BLOQ_POR" | fold -s -w 76 | sed '2,$s/^/    /'; }
[[ -n "$BLOQUEA"  ]] && { echo; echo -e "  ${YELLOW}ESTE ÍTEM BLOQUEA:${NC} $BLOQUEA" | fold -s -w 76 | sed '2,$s/^/    /'; }
[[ -n "$AVISO_O"  ]] && { echo; echo -e "  ${YELLOW}COSTE (ola):${NC} $AVISO_O" | fold -s -w 76 | sed '2,$s/^/    /'; }
[[ -n "$AVISO_I"  ]] && { echo; echo -e "  ${YELLOW}COSTE (ítem):${NC} $AVISO_I" | fold -s -w 76 | sed '2,$s/^/    /'; }
echo

[[ $SOLO_ANUNCIAR -eq 1 ]] && exit 0

# ── El ítem está bien escrito ───────────────────────────────────────────────
# Va ANTES de las puertas de gasto y antes de arrancar `claude`: un ítem sin
# plan de reversión escrito no debe consumir ni tokens ni horas de máquina. Los
# slash commands ya validaban, pero al CERRAR, que es tarde para no gastar.
# El fallo se ve entero (el validador dice qué campo falta) y se puede saltar
# con --igual, como las demás guardas.
if ! python3 "$SCRIPT_DIR/validar-ledger.py" --item "$ID" "$LEDGER"; then
  if [[ $FORZAR -eq 0 ]]; then
    echo -e "${RED}✗${NC} No lanzo ${BOLD}$ID${NC}: la ficha está incompleta."
    echo -e "${DIM}   Complétala en $LEDGER, o añade --igual para ejecutarlo así.${NC}"
    exit 1
  fi
  echo -e "${YELLOW}⚠${NC}  Ficha incompleta, sigo por --igual."
fi

# El resto del ledger no bloquea este ítem, pero un id duplicado o un `ola` como
# string hacen que la PRÓXIMA invocación elija mal, y eso se descubre tarde.
if ! SALIDA_LEDGER="$(python3 "$SCRIPT_DIR/validar-ledger.py" "$LEDGER" 2>&1)"; then
  echo -e "${YELLOW}⚠${NC}  El ledger tiene problemas (no bloquean este ítem):"
  sed 's/^/     /' <<<"$SALIDA_LEDGER"
  echo
fi

# ── Puertas antes de gastar ─────────────────────────────────────────────────
# Las mismas tres condiciones se juzgan distinto según el modo: con alguien
# delante se preguntan, y sin nadie delante se rechazan. Una pregunta que nadie
# puede responder no es una puerta, es un cuelgue.
ARBOL_SUCIO=0
git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet || ARBOL_SUCIO=1
CARO=0
awk "BEGIN{exit !($HORAS > 1)}" && CARO=1

if [[ "$MODO" == "desatendido" ]]; then
  RAZONES=()
  [[ $CARO -eq 1 ]]       && RAZONES+=("pide $HORAS h de máquina y nadie podría confirmarlo")
  [[ "$MULTI" == "sí" ]]  && RAZONES+=("lleva multiagente, que el ledger reserva para lo supervisado")
  # El propio ledger ya declara cuánto criterio hace falta: `opus` es el campo
  # con el que se marca "aquí el CRITERIO es el trabajo". Dejar solo justo eso
  # es dejar solo lo único que el arnés dice que no hay que dejar solo. Estaba
  # escrito en el README y no en el código, que es como una regla no se cumple.
  [[ "$MODELO" == "opus" ]] && RAZONES+=("el ledger lo marca \`opus\`: donde el criterio ES el trabajo, y eso no se deja sin nadie delante")
  [[ -n "$BLOQ_POR" ]]    && RAZONES+=("está bloqueado por $BLOQ_POR")
  [[ $ARBOL_SUCIO -eq 1 ]] && RAZONES+=("el árbol tiene cambios sin commitear y el ítem los arrastraría al commit")
  if [[ ${#RAZONES[@]} -gt 0 && $FORZAR -eq 0 ]]; then
    echo -e "${RED}✗${NC} No lanzo ${BOLD}$ID${NC} desatendido:"
    for r in "${RAZONES[@]}"; do echo "   · $r"; done
    echo -e "${DIM}   Córrelo interactivo (sin --desatendido) o añade --igual si sabes lo que haces.${NC}"
    exit 1
  fi
else
  if [[ -n "$BLOQ_POR" ]]; then
    read -r -p "$(echo -e "${RED}Está bloqueado.${NC} ¿Ejecutar de todas formas? [s/N] ")" r
    [[ "$r" =~ ^[sSyY]$ ]] || { echo "Cancelado."; exit 0; }
  fi
  if [[ $CARO -eq 1 ]]; then
    echo -e "${YELLOW}⚠${NC}  $HORAS horas de máquina. No se lanza por iniciativa propia."
    read -r -p "   ¿Confirmas? [s/N] " r
    [[ "$r" =~ ^[sSyY]$ ]] || { echo "Cancelado."; exit 0; }
  fi
  if [[ $ARBOL_SUCIO -eq 1 ]]; then
    echo -e "${YELLOW}⚠${NC}  El árbol tiene cambios sin commitear. El ítem cierra con commit y los arrastraría."
    git -C "$ROOT" status --short | sed 's/^/     /'
    read -r -p "   ¿Sigo? [s/N] " r
    [[ "$r" =~ ^[sSyY]$ ]] || { echo "Cancelado."; exit 0; }
  fi
fi

# ── Ejecución en contexto limpio ────────────────────────────────────────────
# Sesión nueva: no es un /clear sobre la sesión actual, es otro proceso.
# El nombre (-n) la hace identificable en /resume y en el título del terminal.
NOMBRE="plan $ID"
ARGS_CLAUDE=(-n "$NOMBRE" --model "$MODELO" --effort "$ESFUERZO")

case "$MODO" in
  interactivo)
    echo -e "${GREEN}▶${NC} Sesión nueva ${BOLD}\"$NOMBRE\"${NC} — $MODELO / $ESFUERZO / interactivo"
    echo -e "${DIM}   Apruebas los permisos y las confirmaciones aquí.${NC}"
    ;;
  auto)
    ARGS_CLAUDE+=(--permission-mode auto)
    echo -e "${GREEN}▶${NC} Sesión nueva ${BOLD}\"$NOMBRE\"${NC} — $MODELO / $ESFUERZO / ${YELLOW}auto${NC}"
    echo -e "${DIM}   El clasificador decide los permisos rutinarios; lo destructivo sigue frenando,${NC}"
    echo -e "${DIM}   y sigues estando delante para confirmar una corrida larga.${NC}"
    echo -e "${DIM}   La primera vez, Claude Code te pedirá aceptar el modo auto.${NC}"
    ;;
  desatendido)
    # Las guardas ya se evaluaron arriba: aquí sólo se arma la llamada.
    ARGS_CLAUDE+=(-p --permission-mode acceptEdits --max-budget-usd "$PRESUPUESTO")
    echo -e "${GREEN}▶${NC} ${BOLD}\"$NOMBRE\"${NC} — $MODELO / $ESFUERZO / ${YELLOW}desatendido${NC}, techo \$$PRESUPUESTO"
    [[ ${#RAZONES[@]} -gt 0 ]] && echo -e "   ${RED}Guardas saltadas con --igual.${NC}"
    echo -e "${DIM}   Sin sesión interactiva: revisa el commit al terminar, no durante.${NC}"
    ;;
esac
echo

set +e
claude "${ARGS_CLAUDE[@]}" "/plan-siguiente $ID"
CODE=$?
set -e

echo
echo -e "${BOLD}── Cierre ──${NC}"
git -C "$ROOT" log --oneline -1
git -C "$ROOT" status --short | sed 's/^/  /'

# ── Puertas de cierre ───────────────────────────────────────────────────────
# El ledger se RELEE: lo que importa aquí es cómo quedó el ítem, no cómo estaba
# al empezar. El comando de verificación también se toma de esta relectura, no
# del anuncio: si la sesión lo cambió, se corre el que quedó escrito.
CIERRE="$(python3 - "$LEDGER" "$ID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
for o in d['olas']:
    for it in o['items']:
        if it['id'] == sys.argv[2]:
            print('estado\t' + str(it.get('estado', '?')))
            print('cmd\t' + ' '.join((it.get('verificacion_comando') or '').split()))
PY
)"
ESTADO_FIN=$(sed -n 's/^estado\t//p' <<<"$CIERRE")
VERIF_CMD=$(sed -n 's/^cmd\t//p' <<<"$CIERRE")
echo "  estado en el ledger: ${ESTADO_FIN:-(el ítem ya no está en el ledger)}"

CIERRE_ROTO=0
if [[ "$ESTADO_FIN" != "hecho" ]]; then
  # Un ítem que quedó `en_curso` o `bloqueado` no afirma nada, así que no hay
  # nada que auditarle. El sitio donde se ve que quedó abierto es la línea de
  # estado de arriba.
  :
elif [[ $FORZAR -eq 1 ]]; then
  echo -e "  ${YELLOW}⚠${NC}  Puertas de cierre saltadas por --igual."
else
  # (a) Rastro. `hecho` lo escribió el mismo agente que hizo el trabajo; el
  #     campo `resultado` es lo único de ese cierre que otro puede comprobar.
  if SALIDA_CIERRE="$(python3 "$SCRIPT_DIR/validar-ledger.py" --al-cerrar "$ID" "$LEDGER" 2>&1)"; then
    echo -e "  ${GREEN}✓${NC} $(sed 's/^✓ //' <<<"$SALIDA_CIERRE" | head -1)"
  else
    CIERRE_ROTO=1
    echo -e "  ${RED}✗${NC} El cierre no dejó rastro:"
    sed 's/^/     /' <<<"$SALIDA_CIERRE"
  fi

  # (b) Criterio mecánico. Se corre AQUÍ, fuera de la sesión que declaró el
  #     ítem hecho: es la diferencia entre "el agente dice que pasa" y "pasa".
  if [[ -n "$VERIF_CMD" ]]; then
    LIMITE="${ARNES_LIMITE_VERIFICACION:-900}"
    echo -e "  ${CYAN}▸${NC} verificando: ${BOLD}$VERIF_CMD${NC} ${DIM}(límite ${LIMITE}s)${NC}"
    LOG_VERIF="$(mktemp)"
    # Perro guardián en vez de `timeout`: coreutils no está en un macOS de
    # serie, y un comando colgado en --desatendido no lo destraba nadie.
    set +e
    ( cd "$ROOT" && bash -c "$VERIF_CMD" ) >"$LOG_VERIF" 2>&1 &
    PID_VERIF=$!
    ( sleep "$LIMITE"; kill -TERM "$PID_VERIF" ) >/dev/null 2>&1 &
    PID_PERRO=$!
    wait "$PID_VERIF"; CODE_VERIF=$?
    kill -TERM "$PID_PERRO" >/dev/null 2>&1
    wait "$PID_PERRO" >/dev/null 2>&1
    set -e
    if [[ $CODE_VERIF -eq 0 ]]; then
      echo -e "  ${GREEN}✓${NC} La verificación del ítem pasa fuera de su propia sesión."
    else
      CIERRE_ROTO=1
      if [[ $CODE_VERIF -ge 128 ]]; then
        echo -e "  ${RED}✗${NC} La verificación no terminó en ${LIMITE}s (se cortó)."
        echo -e "     ${DIM}Sube ARNES_LIMITE_VERIFICACION si el comando es legítimamente lento.${NC}"
      else
        echo -e "  ${RED}✗${NC} La verificación falla (código $CODE_VERIF), pero el ítem quedó \`hecho\`."
      fi
      echo -e "     ${DIM}últimas líneas:${NC}"
      tail -20 "$LOG_VERIF" | sed 's/^/     /'
    fi
    rm -f "$LOG_VERIF"
  fi
fi

if [[ $CIERRE_ROTO -eq 1 ]]; then
  echo
  echo -e "${RED}✗${NC} ${BOLD}$ID${NC} está marcado \`hecho\` pero no lo demuestra."
  echo -e "${DIM}   No se revierte nada: el commit ya existe y deshacerlo es tuyo. La ficha${NC}"
  echo -e "${DIM}   trae el \`rollback\`. Reabrir el ítem es cambiar su estado a \`en_curso\`.${NC}"
  [[ $CODE -eq 0 ]] && CODE=1
fi

echo -e "${DIM}  siguiente: bash $SCRIPT_DIR/plan-run.sh${NC}"
exit $CODE
