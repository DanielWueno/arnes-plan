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
it = d['olas'][0]['items'][0]
# Las notas de la plantilla son prosa, no valores: `verificacion_comando` con
# un párrafo dentro se ejecutaría como shell. Cada prueba pone el suyo.
for nota in ('verificacion_comando', '_resultado'):
    it.pop(nota, None)
it.update(
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


# ── A partir de aquí hace falta un `claude` que además CIERRE el ítem, que es
# la única forma de probar unas puertas que sólo se abren cuando el ledger
# vuelve marcado `hecho`. Se controla por entorno para no escribir cuatro.
cat > "$TMP/bin/claude" <<'FAKE'
#!/bin/bash
echo "[claude-falso] $*"
if [[ -n "${FALSO_CIERRA:-}" ]]; then
python3 - <<'PY'
import json, os
p = os.environ['FALSO_LEDGER']
d = json.load(open(p, encoding='utf-8'))
it = d['olas'][0]['items'][0]
it['estado'] = os.environ['FALSO_CIERRA']
r = os.environ.get('FALSO_RESULTADO', '')
if r: it['resultado'] = r
else: it.pop('resultado', None)
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY
fi
exit 0
FAKE
chmod +x "$TMP/bin/claude"
export FALSO_LEDGER="$PROY/docs/plan/ejecucion-plan.estado.json"

ficha() { # ficha <campo=valor>...  — deja el ledger así y el árbol limpio
  python3 - "$@" <<'PY'
import json, sys
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
it = d['olas'][0]['items'][0]
for par in sys.argv[1:]:
    k, _, v = par.partition('=')
    if v == '': it.pop(k, None)
    else: it[k] = v
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY
  git add -A && git commit -qm "estado de prueba" --allow-empty
}

echo "4. El ledger dice \`opus\` = no se deja sin nadie delante"
ficha modelo=opus
SALIDA="$(bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "se niega a lanzarlo desatendido"  "1"  "$CODE"
check "no se invocó a claude"            "0"  "$(grep -c 'claude-falso' <<<"$SALIDA")"
check "dice que la razón es el modelo"   "si" "$(grep -q 'opus' <<<"$SALIDA" && echo si || echo no)"
SALIDA="$(bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido --igual </dev/null 2>&1)"
check "--igual la salta"                 "1"  "$(grep -c 'claude-falso' <<<"$SALIDA")"
ficha modelo=haiku

echo "5. Un \`hecho\` sin rastro de qué pasó no cuenta como cerrado"
ficha resultado=
SALIDA="$(FALSO_CIERRA=hecho bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "sale distinto de 0"               "1"  "$CODE"
check "nombra el campo que falta"        "si" "$(grep -q 'resultado' <<<"$SALIDA" && echo si || echo no)"
check "no revierte el commit por su cuenta" "si" "$(grep -q 'No se revierte nada' <<<"$SALIDA" && echo si || echo no)"
git checkout -q docs/plan/ejecucion-plan.estado.json
SALIDA="$(FALSO_CIERRA=hecho FALSO_RESULTADO='evidencia: n/a' bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "con resultado escrito, cierra en verde" "0" "$CODE"
git checkout -q docs/plan/ejecucion-plan.estado.json

echo "6. La verificación se corre fuera de la sesión que declaró el ítem hecho"
ficha verificacion_comando='exit 3'
SALIDA="$(FALSO_CIERRA=hecho FALSO_RESULTADO=ok bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "un ítem \`hecho\` que no verifica sale != 0" "1" "$CODE"
check "dice el código de salida real"    "si" "$(grep -q 'código 3' <<<"$SALIDA" && echo si || echo no)"
git checkout -q docs/plan/ejecucion-plan.estado.json

# El riesgo de verdad: que el comando corra donde vive el arnés en vez de donde
# vive el proyecto. Este fichero sólo existe en la raíz del consumidor.
ficha verificacion_comando='test -f docs/plan/ejecucion-plan.estado.json'
SALIDA="$(FALSO_CIERRA=hecho FALSO_RESULTADO=ok bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "corre en la raíz del proyecto, no en la del arnés" "0" "$CODE"
git checkout -q docs/plan/ejecucion-plan.estado.json

# Un ítem que NO cerró no afirma nada: verificarlo sólo produciría un rojo que
# confunde. El comando falla siempre, así que si se corriera se notaría.
ficha verificacion_comando='exit 3'
SALIDA="$(FALSO_CIERRA=en_curso bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "si el ítem no cerró, no se verifica" "0" "$CODE"
check "y no dice que verifique nada"     "0"  "$(grep -c 'verificando:' <<<"$SALIDA")"
git checkout -q docs/plan/ejecucion-plan.estado.json

# Sin perro guardián, esto colgaría la sesión desatendida para siempre.
ficha verificacion_comando='sleep 30'
SALIDA="$(ARNES_LIMITE_VERIFICACION=1 FALSO_CIERRA=hecho FALSO_RESULTADO=ok \
          bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "un comando colgado se corta"      "1"  "$CODE"
check "y dice que fue el límite"         "si" "$(grep -q 'no terminó en 1s' <<<"$SALIDA" && echo si || echo no)"
git checkout -q docs/plan/ejecucion-plan.estado.json

echo
if [[ $FALLOS -eq 0 ]]; then echo "$OK comprobaciones, todas verdes"; exit 0; fi
echo "$FALLOS de $((OK+FALLOS)) comprobaciones en rojo"; exit 1
