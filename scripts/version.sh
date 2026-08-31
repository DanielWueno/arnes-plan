#!/bin/bash
# ============================================================
# version.sh — Lo que `arnes --version` contesta.
# ============================================================
# Por qué existe: hasta 1.11.0 `arnes --version` caía en el "Bandera
# desconocida" de plan-run.sh y salía 1; `-V` y `version` era peor, se
# interpretaban como id de ítem y contestaban "No hay ítem que encaje con: -V".
# El número existía, pero sólo dentro de `--help`, entre cuarenta líneas de
# banderas. Un `--version` es la primera cosa que se teclea cuando algo no
# cuadra, y la que se pide en un informe de fallo.
#
# UNA línea en stdout, siempre, y nada más. Deliberadamente NO lleva la ruta de
# instalación ni el diagnóstico: eso es otra pregunta —"¿dónde está y está
# sana?"— y la contesta `arnes doctor`. Mezclarlas rompe lo que cualquiera
# espera de `--version`, y rompe `arnes --version | ...` en un script.
#
# El sha sí va, porque el sha es identidad igual que el número: dos 1.12.0 con
# distinto commit son código distinto, y en un plugin que se instala desde una
# rama eso pasa. La ruta es ubicación, que es otra cosa.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/entorno.sh"

VERSION="$(arnes_version_plugin "$SCRIPT_DIR")"

# El sha: primero git —la verdad sobre el código que corre—, y si no hay
# repositorio, el del registro, pero SÓLO si la copia que corre es la
# registrada. Sobre cualquier otra copia el sha del registro es de otro código.
SHA="$(arnes_sha_git "$SCRIPT_DIR/.." || true)"
AVISO=""
if [[ -z "$SHA" ]]; then
  REG="$(arnes_registro)"
  RUTA="${REG%%$'\t'*}"
  if [[ -n "$RUTA" && "$SCRIPT_DIR" == "$RUTA/scripts" ]]; then
    SHA="$(cut -f3 <<<"$REG")"
  elif [[ -n "$RUTA" ]]; then
    # Se omite en vez de inventarse. Y se dice, pero por stderr: stdout es una
    # línea y tiene que seguir siendo pegable en un pipe.
    AVISO="esta no es la copia instalada; sin sha comprobable. Detalle: arnes doctor"
  fi
fi

if [[ -n "$SHA" ]]; then
  printf 'arnes %s (%s)\n' "$VERSION" "$SHA"
else
  printf 'arnes %s\n' "$VERSION"
fi
[[ -n "$AVISO" ]] && printf 'arnes: %s\n' "$AVISO" >&2
exit 0
