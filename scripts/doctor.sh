#!/bin/bash
# ============================================================
# doctor.sh — `arnes doctor`: ¿esta instalación es coherente?
# ============================================================
# Por qué existe, y por qué separado de `--version`: en este arnés la versión no
# es UNA, son cuatro identidades que se quedan atrás por su cuenta y en silencio.
#
#   · La copia instalada, que es la que se ejecuta.
#   · La que se está ejecutando de verdad, que puede ser otra: una ruta del
#     cache copiada de una consola vieja sigue siendo ejecutable meses después.
#   · El lanzador de ~/.local/bin, que `arrancar` escribe UNA vez y que
#     `claude plugin update` no reescribe nunca.
#   · El esquema del ledger, que viaja en el repositorio DEL PROYECTO. Mientras
#     el arnés vivía dentro de él no podían desincronizarse; como plugin, sí.
#
# Cada una falla tarde y lejos de su causa. Ponerlas en la misma pantalla es lo
# que convierte esto en la respuesta a "algo va raro" y en lo que se pega en un
# informe de fallo. `--version` contesta la otra pregunta —qué código corro— en
# una línea, porque son preguntas distintas.
#
# Informa; no arregla nada por su cuenta. La excepción es `--limpiar`, que se
# pide a mano: el doctor a secas ya lista lo que borraría, así que él es el
# ensayo en seco y no hace falta un segundo verbo para confirmarlo.
#
# Código de salida: 1 sólo si hay algo ROTO —una copia que no es la instalada,
# un esquema de ledger que este arnés no sabe leer, un requisito que falta—.
# La deriva informativa (copias viejas, lanzador sin marca, versión disponible
# sin instalar) sale 0: un doctor que se pone rojo por lo normal deja de leerse.
# ============================================================
set -uo pipefail

B=$'\033[1m'; D=$'\033[2m'; G=$'\033[0;32m'; Y=$'\033[1;33m'; R=$'\033[0;31m'; N=$'\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/entorno.sh"
RAIZ_PLUGIN="$(cd "$SCRIPT_DIR/.." && pwd)"

LIMPIAR=0
for a in "$@"; do
  case "$a" in
    --limpiar) LIMPIAR=1 ;;
    -h|--help) awk '/^# ={10,}$/{n++; if(n==3) exit} NR>1{sub(/^# ?/,""); print}' \
                   "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "arnes doctor: no conozco '$a' (sólo --limpiar)" >&2; exit 1 ;;
  esac
done

PROBLEMAS=0
problema() { PROBLEMAS=$((PROBLEMAS+1)); printf "  ${R}✗${N} %s\n" "$1"; }

# Las rutas se acortan a ~: una pantalla de diagnóstico que se pega en un
# informe no tiene por qué llevar el nombre de usuario de nadie.
# El `~` va en una variable a propósito: en la sustitución de un parámetro,
# `\~` deja la barra literal en la salida y `~` a secas se expande de vuelta al
# HOME, deshaciendo justo lo que se quería.
TILDE='~'
corto() { printf '%s' "${1/#$HOME/$TILDE}"; }

VERSION="$(arnes_version_plugin "$SCRIPT_DIR")"
SHA_GIT="$(arnes_sha_git "$RAIZ_PLUGIN" || true)"
REG="$(arnes_registro)"
REG_RUTA="";  REG_VER="";  REG_SHA=""
if [[ -n "$REG" ]]; then
  REG_RUTA="$(cut -f1 <<<"$REG")"; REG_VER="$(cut -f2 <<<"$REG")"; REG_SHA="$(cut -f3 <<<"$REG")"
fi

printf "${B}arnes %s${N}" "$VERSION"
[[ -n "$SHA_GIT" ]] && printf " ${D}(%s)${N}" "$SHA_GIT"
[[ -z "$SHA_GIT" && -n "$REG_SHA" && "$SCRIPT_DIR" == "$REG_RUTA/scripts" ]] && \
  printf " ${D}(%s)${N}" "$REG_SHA"
printf "\n\n"

# ── Instalación ─────────────────────────────────────────────────────────────
printf "${B}INSTALACIÓN${N}\n"
if [[ -z "$REG_RUTA" ]]; then
  printf "  registrada  ${Y}ninguna${N} ${D}— no hay plugin instalado en este HOME${N}\n"
  printf "              ${D}Instalar:  claude plugin install arnes-plan@dweno-forge${N}\n"
else
  printf "  registrada  %-8s %s\n" "$REG_VER" "$(corto "$REG_RUTA")"
  if [[ "$SCRIPT_DIR" == "$REG_RUTA/scripts" ]]; then
    printf "  corriendo   ${G}✓${N} es la copia registrada\n"
  elif [[ -n "$SHA_GIT" ]]; then
    # El clon de desarrollo no es un error: es donde se trabaja el plugin.
    printf "  corriendo   ${Y}otra copia${N} %s ${D}(clon git, no la instalada)${N}\n" \
           "$(corto "$RAIZ_PLUGIN")"
  else
    problema "Esta NO es la copia instalada del arnés: $(corto "$RAIZ_PLUGIN")"
    printf "              ${D}Usa \`arnes\`: resuelve la instalación en cada ejecución.${N}\n"
  fi
fi

# El lanzador. Su marca la escribe `arrancar`; los escritos antes de 1.12.0 no
# la llevan, y eso NO es un fallo: el lanzador sólo resuelve dónde está el
# plugin y delega, así que quedarse atrás casi nunca se nota. Se informa porque
# "casi nunca" no es "nunca", y porque si un día se nota, aquí está la respuesta.
LANZADOR="$(command -v arnes 2>/dev/null || true)"
[[ -z "$LANZADOR" && -f "$BIN_DIR/arnes" ]] && LANZADOR="$BIN_DIR/arnes"
if [[ -z "$LANZADOR" ]]; then
  printf "  lanzador    ${Y}no instalado${N} ${D}— crear con: arnes arrancar${N}\n"
elif ! grep -q '# arnes-plan:atajo' "$LANZADOR" 2>/dev/null; then
  printf "  lanzador    ${Y}ajeno${N}  %s ${D}— hay un \`arnes\` que no es de este plugin${N}\n" \
         "$(corto "$LANZADOR")"
else
  MARCA="$(sed -n 's/^# arnes-lanzador: \(.*\)$/\1/p' "$LANZADOR" 2>/dev/null | head -1)"
  if [[ -z "$MARCA" ]]; then
    printf "  lanzador    ${D}sin marca${N} %s ${D}(escrito antes de 1.12.0)${N}\n" "$(corto "$LANZADOR")"
  elif [[ -n "$REG_VER" && "$MARCA" != "$REG_VER" ]]; then
    printf "  lanzador    ${Y}%-8s${N} %s ${D}— la instalada es %s; alinear: arnes arrancar${N}\n" \
           "$MARCA" "$(corto "$LANZADOR")" "$REG_VER"
  else
    printf "  lanzador    %-8s %s\n" "$MARCA" "$(corto "$LANZADOR")"
  fi
fi

# ¿Hay una versión más nueva ya descargada y sin instalar? El clon del
# marketplace se actualiza por su cuenta (`marketplace update`, y el propio
# CLI), así que puede ir por delante de lo instalado durante días sin que nada
# lo diga. Se busca por el manifiesto, no por el nombre de la carpeta.
CLON="$("$PY" - <<'PY' 2>/dev/null || true
import json, os, sys
r = os.path.expanduser("~/.claude/plugins/known_marketplaces.json")
try:
    d = json.load(open(r, encoding="utf-8"))
except Exception:
    sys.exit(0)
for _, m in (d.items() if isinstance(d, dict) else []):
    loc = (m or {}).get("installLocation")
    if not loc:
        continue
    man = os.path.join(loc, ".claude-plugin", "plugin.json")
    try:
        if json.load(open(man, encoding="utf-8")).get("name") == "arnes-plan":
            print(loc + "\t" + str(json.load(open(man, encoding="utf-8")).get("version") or ""))
            sys.exit(0)
    except Exception:
        continue
PY
)"
if [[ -n "$CLON" && -n "$REG_VER" ]]; then
  CLON_VER="$(cut -f2 <<<"$CLON")"
  if [[ -n "$CLON_VER" && "$CLON_VER" != "$REG_VER" ]]; then
    printf "  disponible  ${Y}%-8s${N} ${D}en el clon del marketplace, sin instalar${N}\n" "$CLON_VER"
    printf "              ${D}Instalarla:  claude plugin update arnes-plan@dweno-forge${N}\n"
  fi
fi

# ── El proyecto ─────────────────────────────────────────────────────────────
printf "\n${B}PROYECTO${N}\n"
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then ROOT="$CLAUDE_PROJECT_DIR"
else ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; fi
printf "  raíz        %s\n" "$(corto "$ROOT")"
LEDGER="$(cd "$ROOT" 2>/dev/null && "$PY" "$SCRIPT_DIR/ledger_path.py" 2>/dev/null || true)"
if [[ -z "$LEDGER" || ! -f "$LEDGER" ]]; then
  # No es un fallo de la instalación: aquí simplemente no hay plan.
  printf "  ledger      ${D}ninguno en este proyecto — sembrar con: arnes arrancar${N}\n"
else
  # La ruta se acorta a lo que cuelga de la raíz. En Windows el prefijo no
  # encajaba —`ledger_path.py` contesta con backslashes y `git rev-parse` con
  # barras, así que la resta no recortaba nada— y salía la ruta absoluta entera,
  # con el nombre de usuario dentro. Se comparan las dos con barras; es sólo
  # para imprimir, y por eso no se toca $LEDGER: en Windows Python es nativo y
  # sólo abre la forma nativa.
  LEDGER_BARRAS="${LEDGER//\\//}"
  printf "  ledger      %s\n" "${LEDGER_BARRAS#${ROOT//\\//}/}"
  SOPORTADO="$("$PY" -c 'import importlib.util as u,sys
s=u.spec_from_file_location("c", sys.argv[1]); m=u.module_from_spec(s); s.loader.exec_module(m)
print(m.ESQUEMA_SOPORTADO)' "$SCRIPT_DIR/validar_ledger_compat.py" 2>/dev/null || echo '?')"
  ESQ="$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8")).get("schema_version","(sin campo)"))' \
        "$LEDGER" 2>/dev/null || echo '?')"
  if [[ "$ESQ" == "$SOPORTADO" ]]; then
    printf "  esquema     %-8s ${D}(este arnés lee el %s)${N}\n" "$ESQ" "$SOPORTADO"
  else
    problema "el ledger dice esquema $ESQ y este arnés lee el $SOPORTADO"
    printf "              ${D}Detalle campo a campo:  arnes validar${N}\n"
  fi
fi

# ── Requisitos ──────────────────────────────────────────────────────────────
printf "\n${B}ENTORNO${N}\n"
printf "  python      %s ${D}(%s)${N}\n" \
       "$("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || echo '?')" "$PY"
if command -v claude >/dev/null 2>&1; then
  printf "  claude      %s\n" "$(claude --version 2>/dev/null | head -1 || echo '?')"
else
  problema "'claude' no está en el PATH: sin él no se puede abrir la sesión de un ítem"
fi
printf "  sistema     %s\n" "${OSTYPE:-desconocido}"

# ── Copias viejas del cache ─────────────────────────────────────────────────
# El disco no es el problema: son unos megas. Lo es que cada copia vieja sigue
# siendo un arnés ENTERO y ejecutable, con una ruta plausible que alguien pegó
# en un README o dejó en el historial de su terminal. Correr una es el fallo
# que plan-run.sh sabe avisar pero no puede impedir; borrarlas lo impide.
VIEJAS=(); BYTES=0
if [[ -n "$REG_RUTA" && "$REG_RUTA" == */plugins/cache/* ]]; then
  PADRE="$(dirname "$REG_RUTA")"
  ACTUAL="$(basename "$REG_RUTA")"
  for d in "$PADRE"/*; do
    [[ -d "$d" ]] || continue
    [[ "$(basename "$d")" == "$ACTUAL" ]] && continue
    [[ -f "$d/.claude-plugin/plugin.json" ]] || continue   # no es una copia del plugin
    case "$RAIZ_PLUGIN/" in "$d/"*) continue ;; esac        # no borrar lo que corre
    VIEJAS+=("$d")
    BYTES=$((BYTES + $(du -sk "$d" 2>/dev/null | cut -f1 || echo 0)))
  done
fi
MB="$(awk -v k="$BYTES" 'BEGIN{s=sprintf("%.1f", k/1024); sub(/\./, ",", s); print s}')"

if [[ ${#VIEJAS[@]} -gt 0 ]]; then
  printf "\n${B}COPIAS VIEJAS EN EL CACHE${N}\n"
  if [[ $LIMPIAR -eq 1 ]]; then
    for d in "${VIEJAS[@]}"; do
      rm -rf "$d" && printf "  ${G}✓${N} borrada  %s\n" "$(basename "$d")"
    done
    printf "  ${G}✓${N} %d copias fuera, %s MB. Se conserva la instalada (%s).\n" \
           "${#VIEJAS[@]}" "$MB" "$ACTUAL"
  else
    printf "  %d versiones anteriores, %s MB:\n" "${#VIEJAS[@]}" "$MB"
    printf "  ${D}%s${N}\n" "$(printf '%s ' "${VIEJAS[@]##*/}")"
    printf "  ${D}Claude Code no las quita: su barrido descarta plugins que ya no se usan,${N}\n"
    printf "  ${D}no versiones viejas de uno en uso, así que se acumula una por update.${N}\n"
    printf "  ${D}Cada una es un arnés ejecutable con ruta plausible — el disco no es el${N}\n"
    printf "  ${D}problema, correr una por error sí.${N}\n"
    printf "  Quitarlas:  ${B}arnes doctor --limpiar${N}\n"
  fi
fi

# ── Veredicto ───────────────────────────────────────────────────────────────
printf "\n"
if [[ $PROBLEMAS -eq 0 ]]; then
  printf "${G}✓${N} Instalación coherente.\n"
  exit 0
fi
printf "${R}✗${N} %d cosa(s) que arreglar, arriba.\n" "$PROBLEMAS"
exit 1
