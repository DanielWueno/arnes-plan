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
# El comando tiene que ir CUALIFICADO con el nombre del plugin. La forma corta
# responde "Unknown command" y la sesión nueva arranca sin hacer nada — así
# estuvo rota la función principal del arnés desde que se extrajo a plugin,
# invisible para esta suite porque el `claude` de mentira acepta cualquier cosa.
# Por eso la comprobación mira la CADENA que se le pasa, no que no reviente.
check "el slash command va cualificado" \
      "si" "$(grep -q -- '/arnes-plan:plan-siguiente' <<<"$SALIDA" && echo si || echo no)"
check "y no en su forma corta" \
      "0"  "$(grep -c -- ' /plan-siguiente' <<<"$SALIDA")"

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
# `acceptEdits` sólo aprueba EDICIONES, y el protocolo empieza leyendo el ledger
# con un script: en modo -p esa llamada esperaba una aprobación imposible y la
# sesión abría sin hacer nada. Medido contra un claude real; `dontAsk` tampoco
# basta. Se comprueba la bandera, no que no reviente.
check "desatendido corre sin pedir permisos" "si" \
      "$(grep -q -- '--permission-mode bypassPermissions' <<<"$SALIDA" && echo si || echo no)"
check "y con techo de gasto"          "si" \
      "$(grep -q -- '--max-budget-usd' <<<"$SALIDA" && echo si || echo no)"
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


echo "7. El mismo diagrama en dos sitios no puede divergir"
D="python3 $ARNES/scripts/validar-diagramas.py"
$D "$ARNES" >/dev/null 2>&1
check "el repo tal cual: coinciden"      "0" "$?"

# Una copia del repo donde tocar sólo uno de los dos sitios, que es el descuido
# real: se corrige el flujo en el README y la página se queda con el viejo.
COPIA="$TMP/copia"; mkdir -p "$COPIA/docs"
cp "$ARNES/README.md" "$COPIA/README.md"
cp "$ARNES/docs/como-funciona.html" "$COPIA/docs/como-funciona.html"
# La sintaxis de flecha sólo puede aparecer dentro del diagrama: mutar por la
# etiqueta a secas tocaría la prosa de la página, que es otra cosa.
mutar() { # mutar <de> <a>
  python3 - "$COPIA/docs/como-funciona.html" "$1" "$2" <<'PY' || echo "  FALLO no se pudo mutar la página"
import io, sys
p, viejo, nuevo = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding='utf-8').read()
assert viejo in s, f'la página no contiene {viejo!r}'
io.open(p, 'w', encoding='utf-8').write(s.replace(viejo, nuevo, 1))
PY
}

mutar 'C->>C: hace el trabajo' 'C->>C: hace otra cosa'
SALIDA="$($D "$COPIA" 2>&1)"; CODE=$?
check "una etiqueta cambiada: falla"     "1"  "$CODE"
check "dice qué línea no coincide"       "si" "$(grep -q 'hace otra cosa' <<<"$SALIDA" && echo si || echo no)"

# La propiedad complementaria, y es la que hace usable la comprobación: la
# página tiene prosa propia que NO está en el README, y reescribirla no puede
# poner el CI en rojo. Se compara el diagrama, no el documento.
cp "$ARNES/docs/como-funciona.html" "$COPIA/docs/como-funciona.html"
mutar 'El agente que hace el trabajo' 'Quien hace el trabajo'
$D "$COPIA" >/dev/null 2>&1
check "reescribir la prosa NO la rompe"  "0" "$?"

# Y el otro descuido: añadir un diagrama al README y olvidar la página.
cp "$ARNES/docs/como-funciona.html" "$COPIA/docs/como-funciona.html"
printf '\n```mermaid\ngraph TD\n  A-->B\n```\n' >> "$COPIA/README.md"
SALIDA="$($D "$COPIA" 2>&1)"; CODE=$?
check "un diagrama de más: falla"        "1"  "$CODE"
check "dice cuántos hay en cada sitio"   "si" "$(grep -q 'diagrama(s) y' <<<"$SALIDA" && echo si || echo no)"


echo "8. Arrancar en un repo que ya tiene plan no puede pisarlo"
ARRANCAR="bash $ARNES/scripts/arrancar.sh"

# Usuario 1: repositorio virgen. Siembra.
NUEVO="$TMP/usuario1"; mkdir -p "$NUEVO"; cd "$NUEVO"
git init -q . && git config user.email t@t && git config user.name t
SALIDA="$($ARRANCAR </dev/null 2>&1)"; CODE=$?
check "repo virgen: siembra y sale 0"    "0"  "$CODE"
check "el ledger existe"                 "si" "$(test -f docs/plan/ejecucion-plan.estado.json && echo si || echo no)"
check "y dice que ahora escribas ítems"  "si" "$(grep -q 'escribe tus ítems' <<<"$SALIDA" && echo si || echo no)"

# Usuario 2: el mismo repo, ya con un plan REAL dentro. Es el caso que el
# `cp` del README destruía sin preguntar.
python3 - <<'PY'
import json
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
d['olas'][0]['items'][0].update(id='1.1-trabajo-de-verdad', titulo='no me borres',
    modelo='haiku', esfuerzo='low', horas_maquina=0, estado='pendiente',
    verificacion='n/a', rollback='n/a', multiagente=False, por_que_este_modelo='x')
d['olas'][0]['items'][0].pop('verificacion_comando', None)
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY
HUELLA_ANTES="$(shasum docs/plan/ejecucion-plan.estado.json | cut -d' ' -f1)"
SALIDA="$($ARRANCAR </dev/null 2>&1)"; CODE=$?
HUELLA_DESPUES="$(shasum docs/plan/ejecucion-plan.estado.json | cut -d' ' -f1)"
check "ledger existente: NO se toca"     "$HUELLA_ANTES" "$HUELLA_DESPUES"
check "y aun así sale 0"                 "0"  "$CODE"
check "dice que no tocó nada"            "si" "$(grep -q 'No se ha tocado nada' <<<"$SALIDA" && echo si || echo no)"
check "y anuncia el ítem que toca"       "si" "$(grep -q 'no me borres' <<<"$SALIDA" && echo si || echo no)"

# Correrlo dos veces seguidas tampoco: idempotencia de verdad, no de palabra.
$ARRANCAR </dev/null >/dev/null 2>&1
check "dos veces seguidas: sigue intacto" "$HUELLA_ANTES" \
      "$(shasum docs/plan/ejecucion-plan.estado.json | cut -d' ' -f1)"

# Y con un destino no convencional ya ocupado, que el resolvedor no mira.
mkdir -p otra/ruta && echo '{"no":"me borres"}' > otra/ruta/ejecucion-plan.estado.json
SALIDA="$(PLAN_LEDGER=/no/existe $ARRANCAR --donde otra/ruta </dev/null 2>&1)"; CODE=$?
check "destino ya ocupado: se niega"     "1"  "$CODE"
check "y el fichero sigue como estaba"   "si" \
      "$(grep -q 'me borres' otra/ruta/ejecucion-plan.estado.json && echo si || echo no)"
cd "$PROY"


echo '9. El atajo arnes resuelve la instalación ACTIVA, no la más nueva'
# Todo contra un HOME de mentira: ni se toca el del usuario ni se depende de
# lo que tenga instalado.
CASA="$TMP/casa"; mkdir -p "$CASA/.local/bin"
CACHE="$CASA/.claude/plugins/cache/arnes-plan/arnes-plan"
mkdir -p "$CACHE/1.0.0/scripts" "$CACHE/2.0.0/scripts"
cat > "$CASA/.claude/plugins/installed_plugins.json" <<PY
{"version":2,"plugins":{"arnes-plan@arnes-plan":[
  {"scope":"user","installPath":"$CACHE/1.0.0","version":"1.0.0"}]}}
PY

cd "$PROY"
HOME="$CASA" bash "$ARNES/scripts/arrancar.sh" >/dev/null 2>&1
check "arrancar instala el atajo"        "si" "$(test -x "$CASA/.local/bin/arnes" && echo si || echo no)"
check "y lleva su firma"                 "si" "$(grep -q 'arnes-plan:atajo' "$CASA/.local/bin/arnes" && echo si || echo no)"

# El caso que importa: el cache tiene una 2.0.0 más alta, pero la INSTALADA es
# la 1.0.0. Elegir por número mayor ejecutaría en silencio código que no está
# activo. Se comprueba sin `claude` en el PATH, que es cuando entra el respaldo.
RESUELVE="$(env HOME="$CASA" PATH=/usr/bin:/bin bash -c \
  'source /dev/stdin <<< "$(sed -n "/^raiz_del_plugin()/,/^}/p" "$0")"; raiz_del_plugin' \
  "$CASA/.local/bin/arnes" 2>/dev/null)"
check "elige la instalada, no la 2.0.0"  "$CACHE/1.0.0" "$RESUELVE"

# --sin-atajo respeta el PATH de quien no lo quiere.
rm -f "$CASA/.local/bin/arnes"
HOME="$CASA" bash "$ARNES/scripts/arrancar.sh" --sin-atajo >/dev/null 2>&1
check "--sin-atajo no instala nada"      "no" "$(test -e "$CASA/.local/bin/arnes" && echo si || echo no)"

# Y no le pisa a nadie un ejecutable suyo que se llame igual.
printf '#!/bin/bash\necho MIO\n' > "$CASA/.local/bin/arnes"; chmod +x "$CASA/.local/bin/arnes"
SALIDA="$(HOME="$CASA" bash "$ARNES/scripts/arrancar.sh" 2>&1)"
check "no sobrescribe un arnes ajeno"    "MIO" "$(bash "$CASA/.local/bin/arnes")"
check "y avisa de que no lo tocó"        "si" "$(grep -q 'no es de este plugin' <<<"$SALIDA" && echo si || echo no)"


echo '10. La puerta de cierre corre por cualquier puerta de entrada'
# El fallo que cierra: las comprobaciones vivían sólo en plan-run.sh, y el flujo
# diario es /plan-siguiente, donde el protocolo sólo PEDÍA autoevaluarse.
GATE="python3 $ARNES/hooks/puerta-de-cierre.py"
GP="$TMP/gate"; mkdir -p "$GP/docs/plan"; cd "$GP"
git init -q . && git config user.email t@t && git config user.name t
cp "$ARNES/plantillas/ledger.plantilla.json" docs/plan/ejecucion-plan.estado.json
LG="$GP/docs/plan/ejecucion-plan.estado.json"

ficha_gate() { # ficha_gate <estado> <comando> [resultado]
  python3 - "$@" <<'PY'
import json, sys
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8')); it = d['olas'][0]['items'][0]
it.pop('_resultado', None)
it.update(id='1.1-x', titulo='x', modelo='haiku', esfuerzo='low', horas_maquina=0,
          estado=sys.argv[1], verificacion='x', rollback='x', multiagente=False,
          por_que_este_modelo='x', verificacion_comando=sys.argv[2])
if len(sys.argv) > 3 and sys.argv[3]: it['resultado'] = sys.argv[3]
else: it.pop('resultado', None)
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY
}
# printf, no echo: `echo {...}` dispara la expansión de llaves de bash y el
# hook recibiría JSON roto, saliendo callado. Un falso verde de manual.
llamar_gate() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "${1:-$LG}" \
    | CLAUDE_PROJECT_DIR="$GP" $GATE 2>&1
}

ficha_gate pendiente 'true'; git add -A; git commit -qm base

ficha_gate hecho 'true'
check "cerrar sin resultado: se queja"   "si" "$(grep -q 'sin .resultado' <<<"$(llamar_gate)" && echo si || echo no)"

ficha_gate hecho 'echo rojo-de-verdad; exit 7' 'evidencia: commit abc'
SALIDA="$(llamar_gate)"
check "la verificación se corre AQUÍ"     "si" "$(grep -q 'código 7' <<<"$SALIDA" && echo si || echo no)"
check "y enseña la salida del comando"    "si" "$(grep -q 'rojo-de-verdad' <<<"$SALIDA" && echo si || echo no)"

ficha_gate hecho 'true' 'evidencia: commit abc'
check "cierre bien hecho: silencio"       ""   "$(llamar_gate)"

check "editar otro fichero: ni se mete"   ""   "$(llamar_gate "$GP/README.md")"

# Sin ruido retroactivo: lo ya cerrado antes de esta edición no se re-verifica.
ficha_gate hecho 'exit 7' 'ya estaba'; git add -A; git commit -qm cerrado
python3 -c "
import json; p='docs/plan/ejecucion-plan.estado.json'
d=json.load(open(p,encoding='utf-8')); d['olas'][0]['items'][0]['titulo']='retoque'
json.dump(d,open(p,'w',encoding='utf-8'),indent=2,ensure_ascii=False)"
check "no re-verifica trabajo ya cerrado" ""   "$(llamar_gate)"
cd "$PROY"

echo '13. arnes --help contesta desde la terminal, sin ir al README'
cd "$PROY"
AYUDA="$(bash "$ARNES/scripts/ayuda.sh" 2>&1)"; CODE=$?
check "sale 0"                            "0"  "$CODE"
# Lo que hace que se consulte en vez de ignorarse: los verbos, los modos, los
# slash commands, las variables de entorno y DÓNDE ESTÁS. Si algo de eso vive
# sólo en el README, es documentación, y en una terminal nadie va a buscarla.
for pieza in 'arnes arrancar' '--desatendido' '--solo-anunciar' \
             '/arnes-plan:plan-siguiente' 'PLAN_LEDGER' 'ARNES_LIMITE_VERIFICACION' \
             'AQUÍ Y AHORA' 'siguiente'; do
  check "menciona: $pieza" "si" "$(grep -qF -- "$pieza" <<<"$AYUDA" && echo si || echo no)"
done
# El escape tiene que llegar como carácter: dentro de un heredoc una variable
# con "\033[2m" se imprime literal, y así salió la primera versión.
check "sin escapes ANSI literales"        "0"  "$(grep -c '\\\\033\[' <<<"$AYUDA")"
# Y el atajo tiene que enrutar la ayuda, no reenviarla a plan-run.sh. Se genera
# uno limpio: la sección 9 deja a propósito un `arnes` ajeno en su HOME falso.
CASA13="$TMP/casa13"; mkdir -p "$CASA13"
HOME="$CASA13" bash "$ARNES/scripts/arrancar.sh" --donde otra/ruta13 >/dev/null 2>&1
ATAJO13="$CASA13/.local/bin/arnes"
check "el atajo enruta --help"            "si" \
      "$(grep -q 'ayuda.sh' "$ATAJO13" 2>/dev/null && echo si || echo no)"
check "con respaldo si el plugin es viejo" "si" \
      "$(grep -q 'plan-run.sh" --help' "$ATAJO13" 2>/dev/null && echo si || echo no)"

echo '12. Nada le enseña al usuario la forma corta del comando'
# Cuatro veces mordió hoy el mismo patrón: texto que da por sabido el espacio de
# nombres del plugin. El hook, el README y plan-run.sh ya estaban; el que
# faltaba era el propio protocolo, que le pedía al agente "el comando exacto
# para continuar" sin decirle cuál era — así que se lo inventaba corto, y el
# usuario lo copiaba y se estrellaba. Esto lo cubre de una vez y para siempre.
# El patrón excluye rutas y nombres de fichero: `scripts/plan-siguiente-linea.py`
# no es el comando. Por eso exige que delante no haya un carácter de ruta y que
# detrás no siga un guión.
CORTAS="$(grep -rnE '(^|[^A-Za-z0-9_./-])/plan-(siguiente|estado|arrancar)([^A-Za-z0-9_-]|$)' \
          "$ARNES/commands" "$ARNES/scripts" "$ARNES/hooks" "$ARNES/plantillas" 2>/dev/null \
          | grep -v 'no existe' | grep -v 'no la escribas' || true)"
check "ningún fichero enseña la forma corta" "" "$CORTAS"
check "y el protocolo da la cualificada"     "si" \
      "$(grep -q '/arnes-plan:plan-siguiente' "$ARNES/commands/plan-siguiente.md" && echo si || echo no)"

echo '11. El plugin no publica un ledger propio'
# Pasó de verdad en la 1.4.0: probar `arrancar.sh` con el repositorio del
# plugin como raíz sembró un ledger ahí, y un `git add -A` lo publicó a todos
# los usuarios. Un .gitignore protege del descuido pero no de un `git add -f`.
COLADOS="$(cd "$ARNES" && git ls-files | grep -c 'ejecucion-plan.estado.json' || true)"
check "ningún ledger versionado en el plugin" "0" "$COLADOS"
check "la plantilla sí sigue estando"         "si" \
      "$(test -f "$ARNES/plantillas/ledger.plantilla.json" && echo si || echo no)"

echo
if [[ $FALLOS -eq 0 ]]; then echo "$OK comprobaciones, todas verdes"; exit 0; fi
echo "$FALLOS de $((OK+FALLOS)) comprobaciones en rojo"; exit 1
