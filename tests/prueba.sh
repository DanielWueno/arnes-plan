#!/usr/bin/env bash
# Regresión del arnés. Cubre los tres fallos que la extracción a plugin podía
# introducir, cada uno probado en el escenario de riesgo y no sólo en el
# benigno. Sin red, sin Claude Code, sin tokens: un `claude` de mentira ocupa
# el PATH para que ninguna ruta gaste nada.
#
# Uso: bash tests/prueba.sh
set -uo pipefail

ARNES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OK=0; FALLOS=0

check() { # check <descripcion> <esperado> <obtenido>
  if [[ "$2" == "$3" ]]; then OK=$((OK+1)); echo "  ok    $1"
  else FALLOS=$((FALLOS+1)); echo "  FALLO $1"; echo "        esperado: $2"; echo "        obtenido: $3"; fi
}

# Un proyecto consumidor: otro repositorio, con su propio ledger.
PROY="$TMP/proyecto"; mkdir -p "$PROY/docs/plan"; cd "$PROY"
git init -q . && git config user.email t@t && git config user.name t
cp "$ARNES/plantillas/ledger.plantilla.json" docs/plan/ejecucion-plan.estado.json
python3 - <<'PY'
import json
p='docs/plan/ejecucion-plan.estado.json'
d=json.load(open(p,encoding='utf-8'))
d['olas'][0]['items'][0].update(
    id='1.1-prueba', titulo='ítem de prueba', modelo='haiku', esfuerzo='low',
    horas_maquina=0, estado='pendiente', verificacion='n/a', rollback='n/a',
    multiagente=False, por_que_este_modelo='prueba')
json.dump(d, open(p,'w',encoding='utf-8'), indent=2, ensure_ascii=False)
PY
git add -A && git commit -qm "commit del consumidor"

mkdir -p "$TMP/bin"
printf '#!/bin/bash\necho "[claude-falso] $*"\n' > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

echo "1. La raíz sale del proyecto que se trabaja, no de donde vive el arnés"
SALIDA="$(bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"
check "el cierre lee el git log del consumidor" \
      "si" "$(grep -q 'commit del consumidor' <<<"$SALIDA" && echo si || echo no)"
# Que se leyó el ledger DEL CONSUMIDOR, no otro: su título es único.
check "se anunció el ítem del ledger del consumidor" \
      "si" "$(grep -q 'ítem de prueba' <<<"$SALIDA" && echo si || echo no)"
check "se lanzó con el modelo que dice el ledger" \
      "si" "$(grep -q -- '--model haiku' <<<"$SALIDA" && echo si || echo no)"

echo "2. Un ítem sin plan de reversión no llega a gastar"
python3 - <<'PY'
import json
p='docs/plan/ejecucion-plan.estado.json'
d=json.load(open(p,encoding='utf-8')); del d['olas'][0]['items'][0]['rollback']
json.dump(d, open(p,'w',encoding='utf-8'), indent=2, ensure_ascii=False)
PY
SALIDA="$(bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "sale distinto de 0"            "1" "$CODE"
check "no se invocó a claude"         "0" "$(grep -c 'claude-falso' <<<"$SALIDA")"
check "dice qué campo falta"          "si" "$(grep -q 'rollback' <<<"$SALIDA" && echo si || echo no)"
SALIDA="$(bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido --igual </dev/null 2>&1)"
check "--igual la salta"              "1" "$(grep -c 'claude-falso' <<<"$SALIDA")"
git checkout -q docs/plan/ejecucion-plan.estado.json

echo "3. El validador no lee un esquema de ledger que no conoce"
V="python3 $ARNES/scripts/validar-ledger.py"
$V docs/plan/ejecucion-plan.estado.json >/dev/null 2>&1
check "ledger legado sin el campo: pasa" "0" "$?"
python3 -c "
import json;p='docs/plan/ejecucion-plan.estado.json'
d=json.load(open(p,encoding='utf-8'));d['schema_version']=99
json.dump(d,open('$TMP/futuro.json','w',encoding='utf-8'),indent=2,ensure_ascii=False)"
$V "$TMP/futuro.json" >/dev/null 2>&1
check "esquema del futuro: se niega"     "1" "$?"

echo
if [[ $FALLOS -eq 0 ]]; then echo "$OK comprobaciones, todas verdes"; exit 0; fi
echo "$FALLOS de $((OK+FALLOS)) comprobaciones en rojo"; exit 1
