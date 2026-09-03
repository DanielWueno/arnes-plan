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
cp "$ARNES/docs/index.html" "$COPIA/docs/index.html"
# La sintaxis de flecha sólo puede aparecer dentro del diagrama: mutar por la
# etiqueta a secas tocaría la prosa de la página, que es otra cosa.
mutar() { # mutar <de> <a>
  python3 - "$COPIA/docs/index.html" "$1" "$2" <<'PY' || echo "  FALLO no se pudo mutar la página"
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
cp "$ARNES/docs/index.html" "$COPIA/docs/index.html"
mutar 'El agente que hace el trabajo' 'Quien hace el trabajo'
$D "$COPIA" >/dev/null 2>&1
check "reescribir la prosa NO la rompe"  "0" "$?"

# Y el otro descuido: añadir un diagrama al README y olvidar la página.
cp "$ARNES/docs/index.html" "$COPIA/docs/index.html"
printf '\n```mermaid\ngraph TD\n  A-->B\n```\n' >> "$COPIA/README.md"
SALIDA="$($D "$COPIA" 2>&1)"; CODE=$?
check "un diagrama de más: falla"        "1"  "$CODE"
check "dice cuántos hay en cada sitio"   "si" "$(grep -q 'diagrama(s) y' <<<"$SALIDA" && echo si || echo no)"


echo "8. Arrancar en un repo que ya tiene plan no puede pisarlo"
CASA8="$TMP/casa8"; mkdir -p "$CASA8"
ARRANCAR="env HOME=$CASA8 bash $ARNES/scripts/arrancar.sh"

# Usuario 1: repositorio virgen. Siembra.
NUEVO="$TMP/usuario1"; mkdir -p "$NUEVO"; cd "$NUEVO"
git init -q . && git config user.email t@t && git config user.name t
SALIDA="$($ARRANCAR </dev/null 2>&1)"; CODE=$?
check "repo virgen: siembra y sale 0"    "0"  "$CODE"
check "el ledger existe"                 "si" "$(test -f docs/plan/ejecucion-plan.estado.json && echo si || echo no)"
check "y dice que ahora escribas ítems"  "si" "$(grep -q 'escribe tus ítems' <<<"$SALIDA" && echo si || echo no)"
# Lo que se imprime para copiar tiene que ser ejecutable tal cual. La misma
# regla que ya cumple `ayuda.sh`: `$ARNES` sólo existe si el lector la exportó.
check "y no imprime \$ARNES sin resolver"  "0"  "$(grep -c '\$ARNES' <<<"$SALIDA" || true)"

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
# Se sourcea TODO lo anterior al `case`, no sólo la función: el atajo resuelve
# el intérprete por encima de ella —en Windows es `python`, no `python3`— y
# extraer sólo el cuerpo dejaba esa variable sin definir. La prueba se rompió
# al hacer el arnés agnóstico de plataforma, y tenía razón en romperse.
RESUELVE="$(env HOME="$CASA" PATH=/usr/bin:/bin bash -c \
  'source /dev/stdin <<< "$(sed -n "/^set -euo/,/^case /p" "$0" | sed "\$d")"; raiz_del_plugin' \
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

echo '16. El arnés no da consejos de un sistema en otro'
# Se escribió en un macOS y lo daba por supuesto. Un compañero lo instaló en
# Windows/PowerShell: el núcleo funcionó -el ledger se sembró- pero la última
# milla le dio tres instrucciones falsas: `~/.local/bin`, `export PATH=...` y
# `python3`. Un consejo equivocado es peor que ninguno: se sigue, no funciona,
# y parece culpa de quien lo siguió.
for os_falso in darwin24 linux-gnu msys cygwin; do
  ES="$(OSTYPE="$os_falso" bash -c 'source "$0"; echo "$ES_WINDOWS"' \
        "$ARNES/scripts/entorno.sh" 2>/dev/null)"
  esperado=0; case "$os_falso" in msys*|cygwin*) esperado=1 ;; esac
  check "detecta $os_falso" "$esperado" "$ES"
done
CONSEJO_WIN="$(OSTYPE=msys     bash -c 'source "$0"; echo "$CONSEJO_PATH"' "$ARNES/scripts/entorno.sh")"
CONSEJO_NIX="$(OSTYPE=darwin24 bash -c 'source "$0"; echo "$CONSEJO_PATH"' "$ARNES/scripts/entorno.sh")"
check "en Windows no dice export"      "0"  "$(grep -c 'export PATH' <<<"$CONSEJO_WIN")"
check "en Windows habla de PowerShell" "si" "$(grep -q 'env:Path' <<<"$CONSEJO_WIN" && echo si || echo no)"
# `$env:Path` de un proceso es la PATH de máquina y la de usuario ya fundidas:
# volcarla en el ámbito "User" copia allí las entradas del sistema para siempre.
# El consejo tiene que leer el ámbito que va a escribir.
check "lee la PATH de usuario antes de escribirla" "si" \
      "$(grep -q 'GetEnvironmentVariable("Path", "User")' <<<"$CONSEJO_WIN" && echo si || echo no)"
check "y no vuelca la PATH del proceso"            "0"  \
      "$(grep -c 'SetEnvironmentVariable("Path", $env:Path' <<<"$CONSEJO_WIN" || true)"
check "en Unix sí dice export"         "si" "$(grep -q 'export PATH' <<<"$CONSEJO_NIX" && echo si || echo no)"
# El registro automático del PATH en Windows, con un PowerShell de mentira: la
# máquina de integración es Linux, así que lo que se comprueba es el contrato.
STUB="$TMP/stub"; mkdir -p "$STUB"
cat > "$STUB/powershell.exe" <<'STUB_PS'
#!/usr/bin/env bash
{ echo "ARGS: $*"; echo "BIN: ${ARNES_BIN_WIN:-<vacio>}"; } >> "$REGISTRO_STUB"
STUB_PS
cat > "$STUB/cygpath" <<'STUB_CP'
#!/usr/bin/env bash
printf 'C:\\Users\\prueba\\.local\\bin'
STUB_CP
chmod +x "$STUB/powershell.exe" "$STUB/cygpath"
export REGISTRO_STUB="$TMP/registro-ps.txt"; : > "$REGISTRO_STUB"
CODE="$(PATH="$STUB:$PATH" OSTYPE=msys bash -c 'source "$0"; arnes_registrar_path "$HOME/.local/bin"; echo $?' "$ARNES/scripts/entorno.sh")"
check "en Windows registra el PATH y sale 0" "0"  "$CODE"
check "invoca PowerShell sin perfil"         "si" "$(grep -q -- '-NoProfile' "$REGISTRO_STUB" && echo si || echo no)"
# La ruta va por el entorno y no dentro del texto del comando: un nombre de
# usuario con una comilla no puede romper ni ampliar el script que se ejecuta.
check "la ruta viaja por el entorno"         "si" "$(grep -q 'BIN: C:' "$REGISTRO_STUB" && echo si || echo no)"
# El ámbito de máquina pide administrador y afecta a todas las cuentas.
check "nunca escribe el ámbito de máquina"   "0"  "$(grep -c 'Machine' "$ARNES/scripts/entorno.sh" || true)"
check "y lee el de usuario antes de escribirlo" "si" \
      "$(grep -q 'GetEnvironmentVariable("Path", "User")' "$ARNES/scripts/entorno.sh" && echo si || echo no)"
# Sin PowerShell no se inventa nada: se cae al consejo impreso, que sigue ahí.
# El PATH tiene que estar vacío de verdad: `/usr/bin:/bin` no vale como "sin
# PowerShell", porque el runner de integración trae `pwsh` instalado.
VACIO="$TMP/sin-powershell"; mkdir -p "$VACIO"
check "sin PowerShell devuelve 1" "1" \
      "$(OSTYPE=msys bash -c 'PATH="$1"; source "$0"; arnes_registrar_path /x; echo $?' \
         "$ARNES/scripts/entorno.sh" "$VACIO")"
check "en Unix no toca el PATH"   "1" \
      "$(OSTYPE=darwin24 bash -c 'source "$0"; arnes_registrar_path /x; echo $?' "$ARNES/scripts/entorno.sh")"

echo "16b. El envoltorio de Windows tiene que encontrar bash él solo"
# `bash "%~dp0arnes"` a secas fallaba con "'bash' is not recognized": el bash de
# Git for Windows vive en su propia consola y no está en el PATH de Windows. No
# se puede ejecutar cmd desde aquí, así que se fija el contenido generado.
CASA16="$TMP/casa16"; mkdir -p "$CASA16"
REPO16="$TMP/repo16"; mkdir -p "$REPO16"; cd "$REPO16"
git init -q . && git config user.email t@t && git config user.name t
HOME="$CASA16" OSTYPE=msys bash "$ARNES/scripts/arrancar.sh" </dev/null >/dev/null 2>&1
CMD="$CASA16/.local/bin/arnes.cmd"
check "en Windows se escribe el envoltorio" "si" "$(test -f "$CMD" && echo si || echo no)"
check "no invoca 'bash' a secas"            "0"  "$(grep -cE '^bash "' "$CMD" || true)"
check "busca el bash de Git for Windows"    "si" \
      "$(grep -qF 'Git\bin\bash.exe' "$CMD" && echo si || echo no)"
check "y lo busca junto al git del PATH"    "si" \
      "$(grep -q 'where git' "$CMD" && echo si || echo no)"
# El redirector de un `for /f` se escapa con UN circunflejo; con dos, `where`
# recibe un `^` literal y la búsqueda no encuentra nada.
check "el redirector va escapado una vez"   "si" \
      "$(grep -q "where git 2^>nul" "$CMD" && echo si || echo no)"
check "si no hay bash, lo dice y sale 127"  "si" \
      "$(grep -q 'exit /b 127' "$CMD" && echo si || echo no)"
check "propaga el código de salida"         "si" \
      "$(grep -q 'exit /b %ERRORLEVEL%' "$CMD" && echo si || echo no)"
# En Unix ese fichero no se escribe: no estorba, pero tampoco se siembra.
CASA16N="$TMP/casa16nix"; mkdir -p "$CASA16N"
HOME="$CASA16N" OSTYPE=darwin24 bash "$ARNES/scripts/arrancar.sh" </dev/null >/dev/null 2>&1
check "en Unix no se escribe el .cmd"       "no" \
      "$(test -f "$CASA16N/.local/bin/arnes.cmd" && echo si || echo no)"
cd "$ARNES"
# Y que ningún script vuelva a clavar el intérprete.
CLAVADOS=0
for f in plan-run.sh arrancar.sh ayuda.sh; do
  grep -q 'python3 "' "$ARNES/scripts/$f" && CLAVADOS=$((CLAVADOS+1))
done
check "ningún script clava python3"    "0"  "$CLAVADOS"
check "ni el hook"                     "0"  "$(grep -c '"python3 ' "$ARNES/hooks/hooks.json")"

echo '15. La página se puede publicar y se ve sin el visor de artifacts'
# Antes sólo renderizaba dentro del visor: en GitHub no se ve —GitHub enseña el
# código fuente de un .html— y con un doble clic los diagramas salían como texto
# plano. Si se pierde el motor, la página vuelve a ser ilegible fuera y nadie se
# entera hasta que alguien abre el enlace en una reunión.
PAG="$ARNES/docs/index.html"
check "la página está en docs/index.html" "si" "$(test -f "$PAG" && echo si || echo no)"
check "trae su propio motor de mermaid"   "si" \
      "$(grep -q 'mermaid.esm.min.mjs' "$PAG" && echo si || echo no)"
check "y degrada sin red en vez de fallar" "si" \
      "$(grep -q 'catch' "$PAG" && echo si || echo no)"
check "con .nojekyll, para que Pages no la toque" "si" \
      "$(test -f "$ARNES/docs/.nojekyll" && echo si || echo no)"
# La versión está escrita a mano en la página: es una copia del manifiesto, y
# dos copias de un dato divergen solas. La página desplegada llegó a anunciar
# v1.1.0 con el plugin en la 1.8.0 — y una carta de presentación que miente
# sobre su propia versión es peor que no llevarla.
V_MANIFIESTO="$(python3 -c "import json;print(json.load(open('$ARNES/.claude-plugin/plugin.json'))['version'])" 2>/dev/null)"
V_PAGINA="$(grep -oE 'arnes-plan · v[0-9]+\.[0-9]+\.[0-9]+' "$PAG" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
check "la página anuncia la versión real" "$V_MANIFIESTO" "$V_PAGINA"
# La página es la puerta de entrada de quien todavía no tiene el plugin, y las
# instrucciones de instalación están copiadas en tres sitios. La página llegó a
# ofrecer `plugin install` sin registrar antes el marketplace: seguida al pie de
# la letra, la instalación falla diciendo que el plugin no existe.
for f in docs/index.html README.md; do
  check "registra el marketplace antes de instalar: $f" "si" \
        "$(grep -q 'plugin marketplace add DanielWueno/arnes-plan' "$ARNES/$f" && echo si || echo no)"
done
# Y el primer arranque no puede pedirse con `arnes`: ese lanzador lo escribe el
# propio arranque, así que recién instalado el plugin todavía no existe.
check "el primer arranque va por el slash command" "si" \
      "$(grep -q '<b>/arnes-plan:plan-arrancar</b>' "$PAG" && echo si || echo no)"
# `$ARNES` es una variable que el lector define a mano, y sólo si opta por no
# instalar el lanzador. Citarla fuera de ese bloque reparte comandos que fallan
# con "No such file or directory" a quien siguió el camino normal.
FUERA="$(python3 - "$ARNES/README.md" <<'EOPY'
import io, sys
lineas = io.open(sys.argv[1], encoding='utf-8').read().splitlines()
definida = next((i for i, l in enumerate(lineas) if 'export ARNES=' in l), len(lineas))
print(' '.join(str(i + 1) for i, l in enumerate(lineas)
               if '$ARNES' in l and i < definida))
EOPY
)"
check "el README no cita \$ARNES antes de definirla" "" "$FUERA"

# El vocabulario del validador está copiado en la prosa. `esfuerzo` llegó a
# documentarse con tres valores cuando el validador acepta cinco.
for v in low medium high xhigh max; do
  check "el README lista el esfuerzo válido: $v" "si" \
        "$(grep -qF -- "\`$v\`" "$ARNES/README.md" && echo si || echo no)"
done

# Una tabla de Markdown no se reanuda después de un párrafo: las filas que
# quedan sueltas se renderizan como texto plano, y en el fuente no se nota.
HUERFANAS="$(python3 - "$ARNES/README.md" <<'EOPY'
import io, re, sys
texto = io.open(sys.argv[1], encoding='utf-8').read()
malos = []
for bloque in re.split(r'\n\s*\n', texto):
    lineas = bloque.splitlines()
    filas = [l for l in lineas if l.startswith('|')]
    if filas and len(filas) == len(lineas) \
       and not any(re.match(r'^\|[\s:|-]+\|$', f) for f in filas):
        malos.append(filas[0][:40])
print(' | '.join(malos))
EOPY
)"
check "ninguna fila de tabla sin cabecera" "" "$HUERFANAS"

echo '14. El hook no reparte rutas con la versión clavada dentro'
# Claude Code conserva las versiones viejas del plugin. Una consola abierta
# antes de actualizar seguía ofreciendo `bash .../1.2.0/scripts/plan-run.sh`,
# que meses después sigue siendo ejecutable y lanza un comando ya inválido.
# Pasó de verdad. La línea tiene que ofrecer el lanzador, no una ruta.
cd "$PROY"
LINEA="$(python3 "$ARNES/scripts/plan-siguiente-linea.py" 2>/dev/null \
         | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null || true)"
check "no ofrece ninguna ruta del cache" "0" "$(grep -c 'plugins/cache' <<<"$LINEA")"
check "ni un plan-run.sh por ruta"       "0" "$(grep -c 'plan-run.sh' <<<"$LINEA")"
check "y sigue diciendo qué ejecutar"    "si" \
      "$(grep -qE 'arnes|plan-arrancar' <<<"$LINEA" && echo si || echo no)"

# Y la red por si alguien ya tiene una ruta vieja copiada: correrla avisa.
# Con un HOME propio: el aviso compara contra installed_plugins.json, que en una
# máquina sin el plugin instalado no existe. Depender del entorno hacía que esta
# comprobación pasara en el portátil del autor y fallara en el runner, señalando
# una diferencia de máquina en vez de un cambio de comportamiento.
CASA_AVISO="$TMP/casa-aviso"
mkdir -p "$CASA_AVISO/.claude/plugins/cache/arnes-plan/arnes-plan/9.9.9/scripts"
cat > "$CASA_AVISO/.claude/plugins/installed_plugins.json" <<AVISO_FIN
{"version":2,"plugins":{"arnes-plan@arnes-plan":[
  {"scope":"user","installPath":"$CASA_AVISO/.claude/plugins/cache/arnes-plan/arnes-plan/9.9.9",
   "version":"9.9.9"}]}}
AVISO_FIN
SALIDA="$(HOME="$CASA_AVISO" bash "$ARNES/scripts/plan-run.sh" --solo-anunciar 2>&1 || true)"
check "correr una copia no instalada avisa" "si" \
      "$(grep -q 'NO es la copia instalada' <<<"$SALIDA" && echo si || echo no)"
# Y sin registro de instalación no debe inventarse un aviso.
CASA_VACIA="$TMP/casa-vacia"; mkdir -p "$CASA_VACIA"
SALIDA="$(HOME="$CASA_VACIA" bash "$ARNES/scripts/plan-run.sh" --solo-anunciar 2>&1 || true)"
check "sin plugin instalado, no avisa"      "no" \
      "$(grep -q 'NO es la copia instalada' <<<"$SALIDA" && echo si || echo no)"

echo '13. arnes --help contesta desde la terminal, sin ir al README'
cd "$PROY"
AYUDA="$(bash "$ARNES/scripts/ayuda.sh" 2>&1)"; CODE=$?
check "sale 0"                            "0"  "$CODE"
# Si falla en otra máquina, que el log sirva para algo: sin esto, el CI sólo
# dice "esperado 0, obtenido 1" y hay que adivinar desde otro sistema.
[[ $CODE -ne 0 ]] && { echo "        ── salida completa de ayuda.sh ──"; sed 's/^/        /' <<<"$AYUDA"; }
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

echo '17. La vista web sale del ledger y no toca el proyecto'
# El proyecto de prueba de la sección 1 sigue montado y tiene su ledger.
cd "$PROY"
export CLAUDE_PROJECT_DIR="$PROY"
VISTA="$TMP/vista.html"
SALIDA_VER="$(bash "$ARNES/scripts/plan-run.sh" ver --no-abrir --salida "$VISTA" 2>&1)"
check "el verbo \`ver\` sale por plan-run.sh" "si" \
      "$(test -f "$VISTA" && echo si || echo no)"
# Un artefacto generado dentro del repositorio obliga a decidir si se versiona.
# Por eso el destino por defecto es un temporal, y por eso esto se comprueba:
# el fallo sería silencioso hasta que alguien lo commiteara.
check "no deja nada en el árbol de trabajo" "" "$(git status --porcelain)"
for pieza in 'btn-guardar' 'btn-resumen' 'ítem de prueba' 'Lo siguiente que toca'; do
  check "la página trae: $pieza" "si" "$(grep -qF -- "$pieza" "$VISTA" && echo si || echo no)"
done
# La página tiene que abrirse sin red: ni CDN, ni fuentes, ni imágenes remotas.
# Un enlace normal (`<a href>`) no dispara ninguna carga al abrir la página —
# el pie de página ahora lleva dos, a propósito (documentación del proyecto y
# del arnés)—, así que sólo cuenta como "pide algo al exterior" un recurso que
# SÍ se cargaría solo: `src=` en cualquier etiqueta, o el `href=` de un `<link>`
# (hoja de estilo, preconexión, etc.).
check "no carga recursos remotos" "0" \
      "$(grep -coE 'src="https?://' "$VISTA" || true)"
check "no enlaza hojas de estilo ni precarga nada del exterior" "0" \
      "$(grep -coE '<link[^>]*href="https?://' "$VISTA" || true)"
# Regresión exacta de un fallo real: el bloque de JavaScript vivía en una cadena
# normal de Python, así que su `\n` se convirtió en un salto de línea DENTRO de
# un literal JavaScript y rompió el script entero — con él, los tres botones y
# el plegado, sin un solo error visible en la página. Se comprueba que el escape
# sigue siendo un escape.
check "el escape del JS no se ha expandido" "si" \
      "$(grep -qF "'<!doctype html>\\n'+doc.outerHTML" "$VISTA" && echo si || echo no)"
if command -v node >/dev/null 2>&1; then
  python3 - "$VISTA" "$TMP/pagina.js" <<'PY'
import re, sys
h = open(sys.argv[1], encoding='utf-8').read()
open(sys.argv[2], 'w', encoding='utf-8').write(re.search(r'<script>(.*?)</script>', h, re.S).group(1))
PY
  check "y el JavaScript compila" "si" \
        "$(node --check "$TMP/pagina.js" >/dev/null 2>&1 && echo si || echo no)"
fi

echo '18. --live no exige haber corrido `ver` antes, y se mantiene al día'
# El contrato que se pidió: --live genera la página si no está o si el ledger es
# más nuevo. Si no, el archivo que alguien comparte puede ser de anteayer.
DEST_LIVE="$(python3 -c "
import sys; sys.path.insert(0, '$ARNES/scripts')
import ver; print(ver.destino_temporal('$PROY'))")"
rm -rf "$(dirname "$DEST_LIVE")"
python3 "$ARNES/scripts/ver.py" --live --puerto 7399 --no-abrir >"$TMP/live.log" 2>&1 &
PID_LIVE=$!
PIDE() { python3 -c "
import sys, urllib.request
try:
    print(urllib.request.urlopen('http://127.0.0.1:7399/' + sys.argv[1], timeout=5).read().decode('utf-8'))
except Exception as exc:
    print('ERROR %s' % exc)" "$1"; }
for _ in $(seq 1 40); do [[ "$(PIDE __cambio)" == ERROR* ]] || break; sleep 0.25; done
check "--live generó la página que no existía" "si" \
      "$(test -f "$DEST_LIVE" && echo si || echo no)"
check "y la sirve" "si" "$(PIDE '' | grep -q 'Plan de ingeniería' && echo si || echo no)"
M1="$(PIDE __cambio)"
python3 - "$PROY/docs/plan/ejecucion-plan.estado.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['olas'][0]['items'][0]['titulo'] = 'CENTINELA-EN-CALIENTE'
json.dump(d, open(sys.argv[1], 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY
sleep 1
check "el ledger cambiado se nota"      "si" "$([[ "$M1" != "$(PIDE __cambio)" ]] && echo si || echo no)"
check "y la página servida se regenera" "si" "$(PIDE '' | grep -q 'CENTINELA-EN-CALIENTE' && echo si || echo no)"
# El archivo del disco es el que se comparte: tiene que ir al día él también, no
# sólo lo que se ve en el navegador.
check "y el archivo del disco también"  "si" \
      "$(grep -q 'CENTINELA-EN-CALIENTE' "$DEST_LIVE" && echo si || echo no)"
# Un ledger a medio escribir es el estado normal mientras alguien lo edita: si
# tumbara el servidor, --live sería inservible justo cuando más se mira.
cp "$PROY/docs/plan/ejecucion-plan.estado.json" "$TMP/ledger-bueno.json"
printf '{ roto' > "$PROY/docs/plan/ejecucion-plan.estado.json"
check "un ledger roto no tumba el servidor" "si" \
      "$(PIDE '' | grep -q 'no se puede leer' && echo si || echo no)"
cp "$TMP/ledger-bueno.json" "$PROY/docs/plan/ejecucion-plan.estado.json"
check "y se recupera al arreglarlo"         "si" \
      "$(PIDE '' | grep -q 'CENTINELA-EN-CALIENTE' && echo si || echo no)"
kill $PID_LIVE 2>/dev/null; wait $PID_LIVE 2>/dev/null
rm -rf "$(dirname "$DEST_LIVE")"
cd "$ARNES"

echo '19. La documentación cuenta lo mismo que hace el código'
SALIDA_DOCS="$(bash "$ARNES/scripts/plan-run.sh" docs --no-abrir 2>&1)"
check "el verbo \`docs\` sale por plan-run.sh" "si" \
      "$(grep -q 'index.html' <<<"$SALIDA_DOCS" && echo si || echo no)"
# La copia local es la que corresponde a la versión instalada; la publicada es
# la de `main` y puede no coincidir. Se ofrecen las dos, distinguidas.
check "ofrece también la publicada"          "si" \
      "$(grep -q 'github.io' <<<"$SALIDA_DOCS" && echo si || echo no)"
check "y avisa de que puede no ser la misma" "si" \
      "$(grep -q 'puede no ser' <<<"$SALIDA_DOCS" && echo si || echo no)"
# El índice de la página no puede prometer secciones que no existen.
ROTOS="$(python3 - "$ARNES/docs/index.html" <<'PY'
import re, sys
h = open(sys.argv[1], encoding='utf-8').read()
ids = set(re.findall(r'id="([a-z-]+)"', h))
print(' '.join(a for a in re.findall(r'href="#([a-z-]+)"', h) if a not in ids))
PY
)"
check "ningún enlace del índice apunta a la nada" "" "$ROTOS"

# Anti-deriva. La documentación de las guardas es una copia en prosa de una
# lista que vive en el código: si alguien añade una sexta guarda y no la
# documenta, nadie se entera hasta que a un usuario le frena algo que la página
# no menciona. Esta cuenta obliga a pasar por aquí.
GUARDAS="$(grep -c 'RAZONES+=(' "$ARNES/scripts/plan-run.sh")"
check "siguen siendo 5 las guardas de --desatendido" "5" "$GUARDAS"
for pieza in 'multiagente' 'opus' 'bloqueado' 'sin commitear' 'más de una hora'; do
  check "la página nombra la guarda: $pieza" "si" \
        "$(grep -qF -- "$pieza" "$ARNES/docs/index.html" && echo si || echo no)"
  check "y el README también: $pieza"        "si" \
        "$(grep -qF -- "$pieza" "$ARNES/README.md" && echo si || echo no)"
done
# Los valores que el validador acepta también están copiados en la página.
for v in haiku sonnet opus low medium high xhigh max \
         pendiente en_curso hecho bloqueado descartado; do
  check "la página lista el valor válido: $v" "si" \
        "$(grep -qF -- "<code>$v</code>" "$ARNES/docs/index.html" && echo si || echo no)"
done

echo '20. La documentación no promete lo que la consola no dice'
cd "$PROY"
export CLAUDE_PROJECT_DIR="$PROY"
check "\`arnes validar\` sale 0 con un ledger bueno" "0" \
      "$(bash "$ARNES/scripts/plan-run.sh" validar >/dev/null 2>&1; echo $?)"
check "y sale 1 con uno roto"                        "1" \
      "$(PLAN_LEDGER=/dev/null bash "$ARNES/scripts/plan-run.sh" validar >/dev/null 2>&1; echo $?)"
check "y contesta por ítem"                          "si" \
      "$(bash "$ARNES/scripts/plan-run.sh" validar --item 1.1 2>&1 | grep -q 'listo para ejecutarse' && echo si || echo no)"
# La tabla de mensajes de la página cita cadenas de la consola. Si alguien
# reescribe un mensaje del script, la tabla queda citando algo que ya nadie ve,
# y quien busque la cadena literal no la encontrará. Se comprueba la cita.
FALSAS="$(python3 - "$ARNES" <<'PY'
import html, io, re, sys
raiz = sys.argv[1]
pag = io.open(raiz + '/docs/index.html', encoding='utf-8').read()
import glob
src = ''.join(io.open(f, encoding='utf-8').read()
              for f in sorted(glob.glob(raiz + '/scripts/*.sh')))
citas = [html.unescape(c) for c in re.findall(r'<code class="dice">(.*?)</code>', pag)]
print(' | '.join(c for c in citas if c not in src))
PY
)"
check "toda cadena citada existe en el script" "" "$FALSAS"
check "y hay cadenas citadas"                  "si" \
      "$(grep -q 'class="dice"' "$ARNES/docs/index.html" && echo si || echo no)"
# Los dos límites de la verificación son distintos según la vía. Documentar sólo
# uno hace que alguien suba la variable a 900 y el hook se la corte a 180.
for n in 900 120 180; do
  check "la página nombra el límite $n" "si" \
        "$(grep -qF -- "$n" "$ARNES/docs/index.html" && echo si || echo no)"
done
# Lo que se imprime para copiar tiene que ser ejecutable tal cual: un `$ARNES`
# sin definir da "No such file or directory" a quien copie la línea.
AYUDA_TXT="$(CLAUDE_PROJECT_DIR="$PROY" bash "$ARNES/scripts/ayuda.sh" 2>&1)"
check "la ayuda no imprime \$ARNES sin resolver" "0" \
      "$(grep -c '\$ARNES' <<<"$AYUDA_TXT" || true)"
# Y ninguna ruta puede llevar la versión dentro: se copia, sobrevive a la
# actualización y acaba ejecutando código viejo. Es la regla que ya cumple el hook.
for f in README.md docs/index.html scripts/ayuda.sh commands/plan-siguiente.md; do
  check "sin rutas con la versión dentro en $f" "0" \
        "$(grep -cE 'arnes-plan/[0-9]+\.[0-9]+\.[0-9]+' "$ARNES/$f" || true)"
done
check "ni la ayuda las imprime" "0" \
      "$(grep -cE 'arnes-plan/[0-9]+\.[0-9]+\.[0-9]+' <<<"$AYUDA_TXT" || true)"
cd "$ARNES"

echo "21. Una arista de bloqueo que el orden lineal no puede honrar"
# El arnés elige por orden de documento y NO lee `bloqueado_por`: la posición
# ES el calendario. Una arista hacia adelante lo lleva a proponer un ítem con
# el bloqueo sin cerrar, avisando pero sin saltarlo.
cd "$ARNES"
FIX="$TMP/bloqueos"; mkdir -p "$FIX"
python3 - "$ARNES" "$FIX" <<'PY'
import json, sys
plantilla, destino = sys.argv[1] + '/plantillas/ledger.plantilla.json', sys.argv[2]
base = json.load(open(plantilla, encoding='utf-8'))
molde = base['olas'][0]['items'][0]

def item(iid, estado, bloqueado_por=None):
    it = dict(molde, id=iid, estado=estado)
    it.pop('resultado', None)
    if estado == 'hecho':
        it['resultado'] = 'Cerrado en el fixture.'
    if bloqueado_por:
        it['bloqueado_por'] = bloqueado_por
    return it

def escribir(nombre, items):
    d = json.loads(json.dumps(base))
    d['olas'] = [dict(base['olas'][0], items=items)]
    json.dump(d, open(f'{destino}/{nombre}.json', 'w', encoding='utf-8'),
              indent=2, ensure_ascii=False)

escribir('fantasma',  [item('1.1-a', 'pendiente', '4.2 (ver el campo bloquea)')])
escribir('adelante',  [item('1.1-a', 'pendiente', '1.2-b'), item('1.2-b', 'pendiente')])
escribir('atras',     [item('1.1-a', 'pendiente'), item('1.2-b', 'pendiente', '1.1-a')])
escribir('cerrado',   [item('1.1-a', 'hecho'),     item('1.2-b', 'pendiente', '1.1-a')])
escribir('historico', [item('1.1-a', 'hecho', '1.2-b'), item('1.2-b', 'pendiente')])
PY
for caso in fantasma adelante; do
  check "\`$caso\`: se niega" "1" \
        "$($V "$FIX/$caso.json" >/dev/null 2>&1; echo $?)"
done
# `pipefail` está activo y el validador sale 1 a propósito, así que la salida se
# captura antes de mirarla: en una tubería, el 1 del validador sería el estado.
FANTASMA="$($V "$FIX/fantasma.json" 2>&1 || true)"
ADELANTE="$($V "$FIX/adelante.json" 2>&1 || true)"
check "el id inexistente se nombra en el error" "si" \
      "$(grep -q 'no es el id de' <<<"$FANTASMA" && echo si || echo no)"
check "y el error de dirección dice dónde mover" "si" \
      "$(grep -q 'Mueve 1.1-a despu' <<<"$ADELANTE" && echo si || echo no)"
check "arista hacia atrás: pasa" "0" \
      "$($V "$FIX/atras.json" >/dev/null 2>&1; echo $?)"
# La dirección sólo se exige a lo que aún va a ejecutarse. Un ítem cerrado no se
# va a mover de sitio, así que reclamársela sería ruido permanente — la misma
# razón por la que `rollback` no se pide hacia atrás.
check "arista hacia adelante en un ítem cerrado: pasa" "0" \
      "$($V "$FIX/historico.json" >/dev/null 2>&1; echo $?)"
# Que el bloqueo haya cerrado NO es un error: pasa cada vez que se cierra algo.
# Pero sin decirlo, el ítem se queda ejecutable y nadie se entera.
check "bloqueante ya cerrado: pasa" "0" \
      "$($V "$FIX/cerrado.json" >/dev/null 2>&1; echo $?)"
CERRADO="$($V "$FIX/cerrado.json" 2>&1 || true)"
check "y lo informa" "si" \
      "$(grep -q '1.2-b esperaba a 1.1-a' <<<"$CERRADO" && echo si || echo no)"

echo "22. \`--version\` contesta siempre, y \`doctor\` mira lo que puede discrepar"
cd "$ARNES"
VERSION_MANIFIESTO="$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])")"

SALIDA="$(bash "$ARNES/scripts/plan-run.sh" --version 2>/dev/null)"; CODE=$?
check "\`--version\` sale 0"                  "0" "$CODE"
check "y trae la versión del manifiesto"      "si" \
      "$(grep -qF "$VERSION_MANIFIESTO" <<<"$SALIDA" && echo si || echo no)"
# UNA línea en stdout, siempre: es lo que hace que `arnes --version | ...` sirva.
# Un aviso, si hay que darlo, va por stderr — de ahí el 2>/dev/null de arriba.
check "y es UNA sola línea"                   "1" "$(wc -l <<<"$SALIDA" | tr -d ' ')"
# El contrato de las dos puertas: `--version` es identidad, no ubicación. Si un
# día alguien le añade la ruta "porque ya que estamos", esto lo frena.
check "sin rutas: la ubicación es cosa de \`doctor\`" "0" \
      "$(grep -cE '/|\\\\' <<<"$SALIDA" || true)"
# Las tres formas, porque las tres se teclean. Hasta 1.11.0 `--version` salía 1
# con "Bandera desconocida" y `-V` y `version` se tomaban por un id de ítem.
for forma in -V version; do
  check "\`$forma\` contesta lo mismo" "$SALIDA" \
        "$(bash "$ARNES/scripts/plan-run.sh" "$forma" 2>/dev/null)"
done
# Y tiene que contestar cuando NADA más funciona: sin ledger, sin `claude` en el
# PATH y con un HOME sin plugin instalado. Es lo primero que se teclea cuando
# algo va mal, y un `--version` que falla por el estado del entorno no sirve
# para diagnosticar ese estado.
CASA22="$TMP/casa22"; mkdir -p "$CASA22"
check "contesta sin ledger, sin claude y sin registro" "0" \
      "$(cd "$TMP" && env HOME="$CASA22" PATH=/usr/bin:/bin \
         bash "$ARNES/scripts/plan-run.sh" --version >/dev/null 2>&1; echo $?)"

# ── doctor ──────────────────────────────────────────────────────────────────
# Instalación coherente: el registro apunta a la copia que se está ejecutando.
CASA_OK="$TMP/casa-doctor-ok"; mkdir -p "$CASA_OK/.claude/plugins"
cat > "$CASA_OK/.claude/plugins/installed_plugins.json" <<DOC_FIN
{"version":2,"plugins":{"arnes-plan@arnes-plan":[
  {"scope":"user","installPath":"$ARNES","version":"$VERSION_MANIFIESTO"}]}}
DOC_FIN
cd "$PROY"
SALIDA="$(HOME="$CASA_OK" CLAUDE_PROJECT_DIR="$PROY" bash "$ARNES/scripts/doctor.sh" 2>&1)"; CODE=$?
check "\`doctor\` sale 0 con una instalación coherente" "0" "$CODE"
[[ $CODE -ne 0 ]] && { echo "        ── salida completa de doctor.sh ──"; sed 's/^/        /' <<<"$SALIDA"; }
check "dice que corre la copia registrada"    "si" \
      "$(grep -q 'es la copia registrada' <<<"$SALIDA" && echo si || echo no)"
check "y nombra el esquema del ledger"        "si" \
      "$(grep -q 'esquema' <<<"$SALIDA" && echo si || echo no)"

# El escenario de riesgo, no el benigno: una copia que NO es la instalada y que
# tampoco es un clon de desarrollo. Sin `.git`, así que no hay sha que la avale.
COPIA="$TMP/copia-suelta"
mkdir -p "$COPIA" && cp -R "$ARNES/scripts" "$ARNES/.claude-plugin" "$COPIA/"
SALIDA="$(HOME="$CASA_OK" CLAUDE_PROJECT_DIR="$PROY" bash "$COPIA/scripts/doctor.sh" 2>&1)"
check "una copia suelta sale 1"               "1" \
      "$(HOME="$CASA_OK" CLAUDE_PROJECT_DIR="$PROY" bash "$COPIA/scripts/doctor.sh" >/dev/null 2>&1; echo $?)"
check "y lo dice"                             "si" \
      "$(grep -q 'NO es la copia instalada' <<<"$SALIDA" && echo si || echo no)"

# Un esquema de ledger que este arnés no sabe leer. Es el fallo que no existía
# mientras el arnés vivía dentro del proyecto: herramienta y ledger viajaban en
# el mismo commit. Como plugin pueden desincronizarse, y en silencio.
PROY22="$TMP/proyecto22"; mkdir -p "$PROY22/docs/plan"
cp "$ARNES/plantillas/ledger.plantilla.json" "$PROY22/docs/plan/ejecucion-plan.estado.json"
python3 - "$PROY22/docs/plan/ejecucion-plan.estado.json" <<'ESQ_FIN'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
d['schema_version'] = 99
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
ESQ_FIN
SALIDA="$(HOME="$CASA_OK" CLAUDE_PROJECT_DIR="$PROY22" bash "$ARNES/scripts/doctor.sh" 2>&1 || true)"
check "un esquema de ledger no soportado sale 1" "1" \
      "$(HOME="$CASA_OK" CLAUDE_PROJECT_DIR="$PROY22" bash "$ARNES/scripts/doctor.sh" >/dev/null 2>&1; echo $?)"
check "y dice qué esquema esperaba"           "si" \
      "$(grep -q 'este arnés lee el' <<<"$SALIDA" && echo si || echo no)"

# ── doctor --limpiar ────────────────────────────────────────────────────────
# El cache acumula una copia por `plugin update`: el barrido de Claude Code
# descarta plugins que ya no se usan, no versiones viejas de uno en uso. Cada
# copia sigue siendo un arnés ejecutable con ruta plausible.
CASA_LIM="$TMP/casa-limpiar"
CACHE_LIM="$CASA_LIM/.claude/plugins/cache/arnes-plan/arnes-plan"
for v in 1.0.0 1.5.0 9.9.9; do
  mkdir -p "$CACHE_LIM/$v/scripts" "$CACHE_LIM/$v/.claude-plugin"
  echo '{"name":"arnes-plan","version":"'"$v"'"}' > "$CACHE_LIM/$v/.claude-plugin/plugin.json"
done
mkdir -p "$CASA_LIM/.claude/plugins"
cat > "$CASA_LIM/.claude/plugins/installed_plugins.json" <<LIM_FIN
{"version":2,"plugins":{"arnes-plan@arnes-plan":[
  {"scope":"user","installPath":"$CACHE_LIM/9.9.9","version":"9.9.9"}]}}
LIM_FIN
SALIDA="$(HOME="$CASA_LIM" CLAUDE_PROJECT_DIR="$PROY" bash "$ARNES/scripts/doctor.sh" 2>&1 || true)"
check "\`doctor\` a secas cuenta las copias viejas y NO borra" "si" \
      "$(grep -q '2 versiones anteriores' <<<"$SALIDA" && test -d "$CACHE_LIM/1.0.0" && echo si || echo no)"
HOME="$CASA_LIM" CLAUDE_PROJECT_DIR="$PROY" bash "$ARNES/scripts/doctor.sh" --limpiar >/dev/null 2>&1 || true
check "\`--limpiar\` quita las viejas"        "no" \
      "$(test -d "$CACHE_LIM/1.0.0" -o -d "$CACHE_LIM/1.5.0" && echo si || echo no)"
check "y conserva la instalada"               "si" \
      "$(test -d "$CACHE_LIM/9.9.9" && echo si || echo no)"

# El escenario de riesgo de este verbo: correrlo DESDE una copia vieja. Borrar
# el suelo que se está pisando dejaría el proceso a medias sobre ficheros que ya
# no existen — y quien corre una copia vieja es exactamente quien más necesita
# que esto no explote.
CASA_PIE="$TMP/casa-pie"
CACHE_PIE="$CASA_PIE/.claude/plugins/cache/arnes-plan/arnes-plan"
mkdir -p "$CACHE_PIE/9.9.9/.claude-plugin" "$CASA_PIE/.claude/plugins"
echo '{"name":"arnes-plan","version":"9.9.9"}' > "$CACHE_PIE/9.9.9/.claude-plugin/plugin.json"
mkdir -p "$CACHE_PIE/1.0.0" && cp -R "$ARNES/scripts" "$ARNES/.claude-plugin" "$CACHE_PIE/1.0.0/"
cat > "$CASA_PIE/.claude/plugins/installed_plugins.json" <<PIE_FIN
{"version":2,"plugins":{"arnes-plan@arnes-plan":[
  {"scope":"user","installPath":"$CACHE_PIE/9.9.9","version":"9.9.9"}]}}
PIE_FIN
HOME="$CASA_PIE" CLAUDE_PROJECT_DIR="$PROY" bash "$CACHE_PIE/1.0.0/scripts/doctor.sh" --limpiar >/dev/null 2>&1 || true
check "no borra la copia desde la que se ejecuta" "si" \
      "$(test -f "$CACHE_PIE/1.0.0/scripts/doctor.sh" && echo si || echo no)"

# El sello del lanzador: sin él, "¿mi lanzador es el de esta versión?" no tiene
# respuesta comprobable, y `claude plugin update` no reescribe ese fichero nunca.
CASA_SELLO="$TMP/casa-sello"; mkdir -p "$CASA_SELLO"
cd "$PROY"
HOME="$CASA_SELLO" bash "$ARNES/scripts/arrancar.sh" >/dev/null 2>&1
check "arrancar sella el lanzador con su versión" "si" \
      "$(grep -q "^# arnes-lanzador: $VERSION_MANIFIESTO$" "$CASA_SELLO/.local/bin/arnes" && echo si || echo no)"
check "y el lanzador sigue ejecutándose"          "0" \
      "$(bash -n "$CASA_SELLO/.local/bin/arnes" >/dev/null 2>&1; echo $?)"
cd "$ARNES"

echo "23. Un bloqueo cuyo bloqueante ya cerró no frena a nadie"
# `bloqueado_por` documenta la arista, no su vigencia: nadie limpia el campo al
# cerrarse el bloqueante. Las puertas preguntaban por la PRESENCIA del campo, así
# que un ítem desbloqueado hacía semanas seguía pidiendo confirmación en
# interactivo y era rechazado en `--desatendido`, para siempre. Se prueban los
# dos lados: el bloqueo vivo tiene que seguir frenando.
cd "$PROY"
fixture_bloqueo() { # fixture_bloqueo <estado del bloqueante>
  python3 - "$1" <<'PY2'
import json, sys
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
molde = dict(d['olas'][0]['items'][0])
for nota in ('verificacion_comando', '_resultado', 'bloqueado_por'):
    molde.pop(nota, None)
molde.update(id='1.0-bloqueante', titulo='el bloqueante', modelo='haiku',
             esfuerzo='low', horas_maquina=0, verificacion='n/a', rollback='n/a',
             multiagente=False, por_que_este_modelo='prueba', estado=sys.argv[1])
if sys.argv[1] == 'hecho':
    molde['resultado'] = 'Cerrado en el fixture.'
    molde.pop('rollback', None)
dependiente = dict(molde, id='1.1-prueba', titulo='ítem de prueba',
                   estado='pendiente', rollback='n/a',
                   bloqueado_por='1.0-bloqueante')
dependiente.pop('resultado', None)
d['olas'][0]['items'] = [molde, dependiente]
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY2
  # El fixture se commitea: el árbol lo dejaron sucio las secciones anteriores y
  # esa guarda dispararía primero, tapando justo lo que aquí se mide.
  git add -A && git commit -qm "fixture de bloqueo ($1)"
}

fixture_bloqueo hecho
SALIDA="$(bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "bloqueante hecho: desatendido lanza"        "0"  "$CODE"
check "y llegó a invocar a claude"                 "si" \
      "$(grep -q 'claude-falso' <<<"$SALIDA" && echo si || echo no)"
check "sin decir que está bloqueado"               "0"  \
      "$(grep -c 'BLOQUEADO POR' <<<"$SALIDA")"
# No basta con callarse: el campo sigue en la ficha y quien lea el ledger lo va
# a ver. Si el arnés no dice por qué no frena, parece que se lo comió.
check "y diciendo por qué no frena"                "si" \
      "$(grep -q 'ya está hecho: no bloquea' <<<"$SALIDA" && echo si || echo no)"
# Los otros dos consumidores del campo, que leen el mismo ledger y sacaban la
# misma conclusión equivocada. El hook es el que más duele: abría CADA sesión
# nueva declarando bloqueado un ítem que no lo está.
LINEA_B="$(python3 "$ARNES/scripts/plan-siguiente-linea.py" 2>/dev/null \
           | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null || true)"
check "el hook no anuncia el bloqueo cerrado"      "0"  "$(grep -c 'BLOQUEADO POR' <<<"$LINEA_B")"
check "y sigue diciendo qué ítem toca"             "si" \
      "$(grep -q '1.1-prueba' <<<"$LINEA_B" && echo si || echo no)"
python3 "$ARNES/scripts/ver.py" --salida "$TMP/ver-bloqueo.html" --no-abrir >/dev/null 2>&1
check "el visor marca la arista ya cerrada"        "si" \
      "$(grep -q 'ya cerrado: no bloquea' "$TMP/ver-bloqueo.html" && echo si || echo no)"
# Marcada, no borrada: la arista es cierta y su historia importa.
check "y no la borra de la ficha"                  "si" \
      "$(grep -q 'Bloqueado por' "$TMP/ver-bloqueo.html" && echo si || echo no)"
# El escenario de riesgo: la guarda tiene que seguir existiendo.
fixture_bloqueo pendiente
SALIDA="$(bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido </dev/null 2>&1)"; CODE=$?
check "bloqueante abierto: desatendido se niega"   "1"  "$CODE"
check "y nombra el bloqueante"                     "si" \
      "$(grep -q 'bloqueado por 1.0-bloqueante' <<<"$SALIDA" && echo si || echo no)"
check "y no gastó nada"                            "0"  "$(grep -c 'claude-falso' <<<"$SALIDA")"
# Para ver el aviso del hook, el bloqueante no puede ser él mismo elegible: el
# hook coge el PRIMER pendiente por orden de documento, y ése sería el
# bloqueante. `bloqueado` lo deja abierto —no cierra la arista— y fuera de la
# elección, que es justo el caso en el que el aviso hace falta.
fixture_bloqueo bloqueado
LINEA_B="$(python3 "$ARNES/scripts/plan-siguiente-linea.py" 2>/dev/null \
           | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null || true)"
check "y el hook sí anuncia el bloqueo vivo"       "si" \
      "$(grep -q 'BLOQUEADO POR: 1.0-bloqueante' <<<"$LINEA_B" && echo si || echo no)"
# Un destino que no está en el ledger cuenta como bloqueo VIVO: ante un id que
# nadie puede resolver, frenar es lo conservador. Sin esto, una errata en el
# campo desactivaría la guarda en silencio, que es peor que el fallo original.
python3 - <<'PY2'
import json
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
d['olas'][0]['items'][1]['bloqueado_por'] = '1.0-bloqueannte'
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY2
SALIDA="$(bash "$ARNES/scripts/plan-run.sh" 1.1 --desatendido --igual </dev/null 2>&1)"
check "un id que no existe cuenta como bloqueo vivo" "si" \
      "$(grep -q 'BLOQUEADO POR' <<<"$SALIDA" && echo si || echo no)"
# El criterio de "cerrado" vive en dos sitios que no se pueden importar entre
# sí: la constante del validador y el literal del resolutor de `plan-run.sh`. Si
# alguien añade un estado a CERRADOS, esto falla y señala dónde está el gemelo.
check "los dos criterios de cerrado no han divergido" "{'hecho'}" \
      "$(sed -n "s/^CERRADOS = //p" "$ARNES/scripts/validar-ledger.py")"
cd "$ARNES"

echo "24. El pie de página nombra la documentación, sin colar un href malicioso"
cd "$PROY"
# El contrato de silencio: sin `documentacion` en la raíz del ledger, no se
# inventa un "no disponible" — sencillamente no hay línea de proyecto.
python3 -c "
import json
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
d.pop('documentacion', None)
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)"
python3 "$ARNES/scripts/ver.py" --salida "$TMP/pie-sin-doc.html" --no-abrir >/dev/null 2>&1
check "sin \`documentacion\`: no aparece la línea del proyecto" "0" \
      "$(grep -c 'Documentación del proyecto' "$TMP/pie-sin-doc.html")"
check "pero sí la del arnés, con su versión y su URL" "si" \
      "$(grep -q "Documentación del arnés (v$VERSION_MANIFIESTO): <a href=\"https://danielwueno.github.io/arnes-plan/\">" "$TMP/pie-sin-doc.html" && echo si || echo no)"

# Con una URL http(s) válida: se pinta como enlace, y la línea del arnés sigue
# ahí al lado.
python3 -c "
import json
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
d['documentacion'] = 'https://ejemplo.invalid/docs'
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)"
python3 "$ARNES/scripts/ver.py" --salida "$TMP/pie-con-doc.html" --no-abrir >/dev/null 2>&1
check "con URL https: aparece como enlace" "si" \
      "$(grep -q '<a href="https://ejemplo.invalid/docs">https://ejemplo.invalid/docs</a>' "$TMP/pie-con-doc.html" && echo si || echo no)"
check "y también sale la URL del arnés con su versión" "si" \
      "$(grep -q "Documentación del arnés (v$VERSION_MANIFIESTO): <a href=\"https://danielwueno.github.io/arnes-plan/\">" "$TMP/pie-con-doc.html" && echo si || echo no)"

# Un esquema peligroso, o directamente basura: nunca dentro de un href, aunque
# sea escapado.
for MALO in 'javascript:alert(1)' 'no-una-url'; do
  python3 -c "
import json, sys
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
d['documentacion'] = sys.argv[1]
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)" "$MALO"
  python3 "$ARNES/scripts/ver.py" --salida "$TMP/pie-malo.html" --no-abrir >/dev/null 2>&1
  check "\`$MALO\` no acaba dentro de un href" "0" \
        "$(grep -c "href=\"$MALO\"" "$TMP/pie-malo.html")"
done
python3 -c "
import json
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
d.pop('documentacion', None)
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)"
git checkout -q docs/plan/ejecucion-plan.estado.json

# El `@media print` no puede tapar las dos líneas nuevas: son justo lo que hace
# falta para encontrar el proyecto y el arnés desde una copia impresa.
BLOQUE_IMPRESION="$(sed -n '/@media print{/,/^}/p' "$TMP/pie-sin-doc.html")"
check "el CSS de impresión no oculta \`.pie-pag\`" "0" \
      "$(grep -c '\.pie-pag[^{]*{[^}]*display:none' <<<"$BLOQUE_IMPRESION")"
check "ni las líneas nuevas por su clase" "0" \
      "$(grep -c '\.linea-doc\|\.linea-arnes' <<<"$BLOQUE_IMPRESION")"
cd "$ARNES"

echo "25. Una ola cerrada a N/N se pliega; la que trae el ítem que toca, no"
cd "$PROY"
python3 - <<'PY'
import json
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
d['olas'] = [
    {"ola": 1, "nombre": "Cerrada del todo", "criterio_de_entrada": "n/a",
     "criterio_de_salida": "n/a", "items": [
        {"id": "1.1-cerrado", "titulo": "uno", "estado": "hecho", "modelo": "haiku"},
        {"id": "1.2-cerrado", "titulo": "dos", "estado": "hecho", "modelo": "haiku"},
    ]},
    {"ola": 2, "nombre": "La que toca", "criterio_de_entrada": "n/a",
     "criterio_de_salida": "n/a", "items": [
        {"id": "2.1-toca", "titulo": "tres", "estado": "pendiente", "modelo": "haiku"},
        {"id": "2.2-toca", "titulo": "cuatro", "estado": "hecho", "modelo": "haiku"},
    ]},
]
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY
python3 "$ARNES/scripts/ver.py" --salida "$TMP/plegado.html" --no-abrir >/dev/null 2>&1
PAG_PLEGADO="$(cat "$TMP/plegado.html")"
# (1) la ola 1 (2/2 hecho, y no es la que anuncia el panel) sale como
# `<details>` SIN `open`; la ola 2 (trae el pendiente que anuncia el panel)
# sale con `open`, aunque por lo demás tampoco esté toda hecha.
check "ola cerrada del todo: \`<details>\` sin \`open\`" "si" \
      "$(grep -qE '<details class="ola" id="ola-1"[^>]*aria-labelledby="t-ola-1">' "$TMP/plegado.html" && echo si || echo no)"
check "y no lleva el atributo \`open\` colado en otro sitio del tag" "0" \
      "$(grep -oE '<details class="ola" id="ola-1"[^>]*>' "$TMP/plegado.html" | grep -c ' open')"
check "ola con el ítem que toca: \`<details ... open>\`" "si" \
      "$(grep -qE '<details class="ola" id="ola-2"[^>]*aria-labelledby="t-ola-2" open>' "$TMP/plegado.html" && echo si || echo no)"
# La cabecera —número, nombre, fracción— vive en el `<summary>`, así que se ve
# siempre, esté la ola abierta o no.
check "la cabecera de la ola plegada vive en el \`<summary>\`" "si" \
      "$(grep -qE '<summary><div class="ola-cab"><h2 id="t-ola-1">.*<span class="frac">2/2</span>' "$TMP/plegado.html" && echo si || echo no)"

# (2) Los anclajes que ya se usan abren el pliegue antes de saltar. Mecánico:
# se comprueba que el JS resuelve la cadena de `<details>` ancestros — incluido
# el caso en que el propio destino de `#ola-N` ES el `<details>`, que la
# revelación nativa del navegador no cubre— y que lo hace tanto en clic como al
# cargar la página con un hash puesto, antes de mover el scroll.
check "el JS sube por los \`<details>\` ancestros del destino" "si" \
      "$(grep -q "tagName==='DETAILS'" "$TMP/plegado.html" && grep -q "closest('details')" "$TMP/plegado.html" && echo si || echo no)"
check "abre antes de hacer scroll, no al revés" "si" \
      "$(python3 -c "
t=open('$TMP/plegado.html',encoding='utf-8').read()
i=t.find('function irA(hash)')
cuerpo=t[i:i+300]
print('si' if cuerpo.find('abrirHasta')<cuerpo.find('scrollIntoView') else 'no')
")"
check "se cablea tanto al clic como al hash de carga" "si" \
      "$(grep -q "addEventListener('click'" "$TMP/plegado.html" && grep -q 'location.hash' "$TMP/plegado.html" && grep -q "addEventListener('hashchange'" "$TMP/plegado.html" && echo si || echo no)"

# (3) `@media print` fuerza todo abierto: por CSS (el `content-visibility`
# oculto de un `<details>` cerrado no basta con `display` a secas si no se
# apunta también ese `content-visibility`) y por JS (`beforeprint`), igual que
# ya hace con `.item.oculto` y `.ola`.
BLOQUE_IMPRESION_OLA="$(sed -n '/@media print{/,/^}/p' "$TMP/plegado.html")"
check "el CSS de impresión reabre el contenido del \`<details>\` cerrado" "si" \
      "$(grep -qE 'details\.ola:not\(\[open\]\)>:not\(summary\)\{[^}]*content-visibility:visible' <<<"$BLOQUE_IMPRESION_OLA" && echo si || echo no)"
check "y el JS fuerza \`open\` en \`beforeprint\`, de respaldo" "si" \
      "$(grep -q "addEventListener('beforeprint'" "$TMP/plegado.html" && echo si || echo no)"

# El escape hatch del rollback: `PLEGAR=False` tiene que devolver el render a
# `<section>` plano, sin un solo `<details>` de ola, y sin `open` colgando.
SIN_PLEGAR="$(python3 -c "
import sys, json
sys.path.insert(0, '$ARNES/scripts')
import ver
ver.PLEGAR = False
datos = json.load(open('docs/plan/ejecucion-plan.estado.json', encoding='utf-8'))
json.dump(datos, open('$TMP/sin-plegar.json', 'w', encoding='utf-8'))
html = ver.generar('$TMP/sin-plegar.json', '0.0.0', '$PROY')
print('si' if ('<details class=\"ola\" id=' not in html and '<section class=\"ola\" id=' in html) else 'no')
")"
check "con \`PLEGAR=False\`, las olas vuelven a \`<section>\` plano" "si" "$SIN_PLEGAR"
git checkout -q docs/plan/ejecucion-plan.estado.json
cd "$ARNES"

echo "26. De la ola 5 a la 2 sin volver arriba a mano"
cd "$PROY"
python3 - <<'PY'
import json
p = 'docs/plan/ejecucion-plan.estado.json'
d = json.load(open(p, encoding='utf-8'))
d['olas'] = [
    {"ola": 1, "nombre": "Primera", "criterio_de_entrada": "n/a",
     "criterio_de_salida": "n/a", "items": [
        {"id": "1.1-nav", "titulo": "uno", "estado": "hecho", "modelo": "haiku"},
        {"id": "1.2-nav", "titulo": "dos", "estado": "hecho", "modelo": "haiku"},
    ]},
    {"ola": 2, "nombre": "Segunda", "criterio_de_entrada": "n/a",
     "criterio_de_salida": "n/a", "items": [
        {"id": "2.1-nav", "titulo": "tres", "estado": "pendiente", "modelo": "haiku"},
        {"id": "2.2-nav", "titulo": "cuatro", "estado": "hecho", "modelo": "haiku"},
    ]},
    {"ola": 3, "nombre": "Tercera", "criterio_de_entrada": "n/a",
     "criterio_de_salida": "n/a", "items": [
        {"id": "3.1-nav", "titulo": "cinco", "estado": "pendiente", "modelo": "haiku"},
    ]},
]
json.dump(d, open(p, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PY
python3 "$ARNES/scripts/ver.py" --salida "$TMP/nav.html" --no-abrir >/dev/null 2>&1

# (1) La barra pegajosa saca una entrada por ola con su fracción, y esa
# fracción no puede ser un cálculo aparte del que ya pinta el mapa de olas:
# se compara, ola por ola, que ambos sitios digan lo mismo.
FRACS="$(python3 -c "
import re
t = open('$TMP/nav.html', encoding='utf-8').read()
mapa = dict(re.findall(r'<a class=\"fila\" href=\"#ola-(\d+)\">.*?<span class=\"frac\">(\d+/\d+)</span>', t))
nav_bloque = re.findall(r'<nav class=\"ola-nav\"[^>]*>(.*?)</nav>', t)[0]
nav = dict(re.findall(r'<a href=\"#ola-(\d+)\"><span class=\"n\">Ola \d+</span><span class=\"frac\">(\d+/\d+)</span></a>', nav_bloque))
ok = mapa and nav and mapa == nav and set(mapa) == {'1','2','3'}
print('mapa=%s nav=%s' % (mapa, nav))
print('IGUAL' if ok else 'DISTINTO')
")"
check "mapa de olas y barra de navegación calculan la MISMA fracción por ola ($FRACS)" "si" \
      "$(echo "$FRACS" | tail -1 | grep -q IGUAL && echo si || echo no)"

# (2) Prev/siguiente: la primera ola no lleva "anterior", la última no lleva
# "siguiente", y la del medio lleva las dos.
check "ola 1 (primera): sin enlace 'anterior'" "si" \
      "$(python3 -c "
t=open('$TMP/nav.html',encoding='utf-8').read()
i=t.find('id=\"ola-1\"'); j=t.find('id=\"ola-2\"')
bloque=t[i:j]
print('si' if ('ola-prev' not in bloque and 'ola-next' in bloque) else 'no')
")"
check "ola 2 (intermedia): lleva anterior Y siguiente" "si" \
      "$(python3 -c "
t=open('$TMP/nav.html',encoding='utf-8').read()
i=t.find('id=\"ola-2\"'); j=t.find('id=\"ola-3\"')
bloque=t[i:j]
print('si' if ('ola-prev' in bloque and 'ola-next' in bloque) else 'no')
")"
check "ola 3 (última): sin enlace 'siguiente'" "si" \
      "$(python3 -c "
t=open('$TMP/nav.html',encoding='utf-8').read()
i=t.find('id=\"ola-3\"'); bloque=t[i:]
print('si' if ('ola-next' not in bloque and 'ola-prev' in bloque) else 'no')
")"

# (3) El botón "arriba" no puede estar visible en la primera pantalla: la
# regla base (sin \`.visible\`) lo esconde, y sólo el JS al hacer scroll
# añade esa clase.
check "hay un enlace/botón \`.arriba\` a \`#top\`" "si" \
      "$(grep -qE '<a class="arriba" href="#top"' "$TMP/nav.html" && echo si || echo no)"
check "por defecto está oculto (visibility:hidden u opacity:0 en la regla base, sin \`.visible\`)" "si" \
      "$(python3 -c "
import re
t=open('$TMP/nav.html',encoding='utf-8').read()
base=re.search(r'\.arriba\{([^}]*)\}', t)
print('si' if base and ('visibility:hidden' in base.group(1) or 'opacity:0' in base.group(1)) else 'no')
")"
check "sólo se revela con una clase que añade el JS al hacer scroll" "si" \
      "$(grep -qE '\.arriba\.visible\{' "$TMP/nav.html" && grep -q "classList.toggle('visible'" "$TMP/nav.html" && grep -q "addEventListener('scroll'" "$TMP/nav.html" && echo si || echo no)"

# (4) @media print no puede colar nada de esto nuevo.
BLOQUE_IMPRESION_NAV="$(sed -n '/@media print{/,/^}/p' "$TMP/nav.html")"
check "\`@media print\` oculta la barra sticky de olas (\`.ola-nav\`)" "si" \
      "$(grep -q '\.ola-nav' <<<"$BLOQUE_IMPRESION_NAV" && echo si || echo no)"
check "\`@media print\` oculta los enlaces anterior/siguiente (\`.ola-vecinas\`)" "si" \
      "$(grep -q '\.ola-vecinas' <<<"$BLOQUE_IMPRESION_NAV" && echo si || echo no)"
check "\`@media print\` oculta el botón \`.arriba\`" "si" \
      "$(grep -q '\.arriba' <<<"$BLOQUE_IMPRESION_NAV" && echo si || echo no)"

# (5) Este ítem no usa scroll suave (\`el.scrollIntoView()\` ya salía sin
# opciones desde 2.1-plegar-por-estado, y los enlaces nuevos son anclas
# normales): se documenta en el propio test que NO hace falta el respaldo de
# \`prefers-reduced-motion\` para scroll, comprobando que no se coló ninguno.
check "no se usó scroll suave en ningún sitio (nada que desactivar para movimiento reducido)" "si" \
      "$(grep -q 'scroll-behavior:smooth' "$TMP/nav.html" && echo no || (grep -q "behavior:.smooth." "$TMP/nav.html" && echo no || echo si))"

git checkout -q docs/plan/ejecucion-plan.estado.json
cd "$ARNES"

echo
if [[ $FALLOS -eq 0 ]]; then echo "$OK comprobaciones, todas verdes"; exit 0; fi
echo "$FALLOS de $((OK+FALLOS)) comprobaciones en rojo"; exit 1
