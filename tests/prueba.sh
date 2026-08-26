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
check "en Unix sí dice export"         "si" "$(grep -q 'export PATH' <<<"$CONSEJO_NIX" && echo si || echo no)"
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
for pieza in 'btn-guardar' 'btn-resumen' 'btn-pdf' 'ítem de prueba' 'Lo siguiente que toca'; do
  check "la página trae: $pieza" "si" "$(grep -qF -- "$pieza" "$VISTA" && echo si || echo no)"
done
# La página tiene que abrirse sin red: ni CDN, ni fuentes, ni imágenes remotas.
check "no pide nada al exterior" "0" \
      "$(grep -coE '(src|href)="https?://' "$VISTA" || true)"
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
src = io.open(raiz + '/scripts/plan-run.sh', encoding='utf-8').read()
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

echo
if [[ $FALLOS -eq 0 ]]; then echo "$OK comprobaciones, todas verdes"; exit 0; fi
echo "$FALLOS de $((OK+FALLOS)) comprobaciones en rojo"; exit 1
