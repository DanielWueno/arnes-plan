#!/bin/bash
# ============================================================
# ayuda.sh — Lo que `arnes --help` debería contestar.
# ============================================================
# Por qué existe: `arnes --help` reenviaba a la cabecera de plan-run.sh, que
# documenta sus banderas pero enseña la forma larga —`bash "$ARNES/plan-run.sh"`—
# que el atajo existe justo para sustituir, y no menciona ni los verbos de
# `arnes`, ni las variables de entorno, ni los slash commands. El resto vivía
# sólo en el README, que es documentación: hay que ir a buscarla, y en una
# terminal nadie la va a buscar.
#
# Termina con el estado real —versión, ledger, ítem siguiente— porque una ayuda
# que además contesta "¿y dónde estoy?" se consulta; una que sólo recita
# banderas, no.
# ============================================================
set -uo pipefail

# Comillas $'...': el escape tiene que ser un CARÁCTER, no la cadena "\033[2m".
# Dentro de un heredoc no hay nada que lo interprete —sólo printf lo haría— y
# se imprimiría literal. Pasó al escribir esto.
B=$'\033[1m'; D=$'\033[2m'; G=$'\033[0;32m'; Y=$'\033[1;33m'; N=$'\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/entorno.sh"
VERSION="$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
           "$SCRIPT_DIR/../.claude-plugin/plugin.json" 2>/dev/null || echo '?')"

cat <<AYUDA
${B}arnes${N} ${D}— ejecuta un plan de ingeniería un ítem por sesión.  v$VERSION${N}

${B}EJECUTAR${N}
  arnes                        el siguiente ítem pendiente, en sesión limpia
  arnes 5.0                    un ítem concreto, por id o por su prefijo
  arnes ola:5                  el siguiente pendiente de esa ola
  arnes --solo-anunciar        la ficha y el coste. No ejecuta ni gasta nada.

${B}CUÁNTA SUPERVISIÓN${N}
  ${D}(nada)${N}                       interactivo: apruebas tú. Es el correcto casi siempre.
  --auto                       el clasificador resuelve los permisos rutinarios;
                               lo destructivo sigue frenando y tú sigues delante.
  --desatendido[=N]            sin sesión ni permisos, con techo de \$N (def. 5).
                               Se niega si el ítem pide más de 1 h, lleva
                               multiagente, dice \`opus\`, está bloqueado, o el
                               árbol tiene cambios sin commitear.
  --igual                      salta esas guardas, y las puertas de cierre.

${B}PREPARAR${N}
  arnes arrancar               deja el proyecto listo. NO pisa un ledger que ya
                               exista; reinstala este atajo si lo borraste.
  arnes arrancar --donde RUTA  sembrar el ledger en otra carpeta
  arnes arrancar --sin-atajo   no instalar el comando \`arnes\`

${B}DENTRO DE CLAUDE CODE${N}
  /arnes-plan:plan-siguiente   ejecuta un ítem y se detiene
  /arnes-plan:plan-estado      el avance, sin ejecutar nada
  /arnes-plan:plan-arrancar    la puesta en marcha, sin rutas
  ${D}Van cualificados con el nombre del plugin; la forma corta no existe.${N}

${B}VARIABLES DE ENTORNO${N}
  PLAN_LEDGER                  ruta del ledger. Manda sobre la búsqueda normal,
                               que mira docs/plan/, docs/analisis-futuro/ y
                               .claude/plan/.
  ARNES_LIMITE_VERIFICACION    segundos que se le dan al \`verificacion_comando\`
                               de un ítem antes de cortarlo (def. 900).
  CLAUDE_PROJECT_DIR           raíz del proyecto. Si no está, se usa la del repo.

${B}COMPROBAR${N}
  "$PY" "\$ARNES/validar-ledger.py"              todo el ledger
  "$PY" "\$ARNES/validar-ledger.py" --item 5.0   ¿está listo para ejecutarse?
  "$PY" "\$ARNES/validar-ledger.py" --al-cerrar 5.0   ¿quedó bien cerrado?
AYUDA

# ── Estado real, que es lo que convierte esto en algo consultable ───────────
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then ROOT="$CLAUDE_PROJECT_DIR"
else ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; fi
LEDGER="$(cd "$ROOT" 2>/dev/null && "$PY" "$SCRIPT_DIR/ledger_path.py" 2>/dev/null || true)"

echo
printf "${B}AQUÍ Y AHORA${N}\n"
printf "  proyecto  %s\n" "$ROOT"
if [[ -n "$LEDGER" ]]; then
  printf "  ledger    %s\n" "$LEDGER"
  SIG="$(cd "$ROOT" && "$PY" - "$LEDGER" <<'PY' 2>/dev/null || true
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
for o in d['olas']:
    for i in o['items']:
        if i['estado'] in ('pendiente', 'en_curso'):
            print(f"{i['id']}  ({i['modelo']}/{i['esfuerzo']}, {i['horas_maquina']} h)")
            raise SystemExit
print('(no quedan ítems pendientes)')
PY
)"
  printf "  siguiente ${G}%s${N}\n" "$SIG"
  printf "${D}  Verlo entero:  arnes --solo-anunciar${N}\n"
else
  printf "  ${Y}ledger    no hay ninguno en este proyecto${N}\n"
  printf "${D}  Crearlo:  arnes arrancar${N}\n"
fi

# Salida explícita. Sin esto, el código lo decide el último comando que se haya
# ejecutado —que cambia según la rama que se tome y según el sistema— y una
# pantalla de ayuda que a veces sale 1 no tiene ningún sentido. El CI de Ubuntu
# la vio fallar donde en macOS salía 0, y esa diferencia no merece un misterio:
# merece un contrato.
exit 0
