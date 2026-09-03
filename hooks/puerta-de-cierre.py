#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Puerta de cierre que corre por CUALQUIER puerta de entrada.

Por qué existe: las comprobaciones de cierre de la 1.1.0 vivían sólo en
`plan-run.sh`, y el flujo diario de la gente es `/arnes-plan:plan-siguiente` dentro de una
sesión. Por ahí el protocolo se limitaba a PEDIRLE al agente que se
autoevaluara — que es exactamente el fallo que esa versión decía haber cerrado,
sobreviviendo en la otra entrada. Se vio en el único consumidor real: cuatro
ítems llegaron a `hecho` sin `resultado` y hubo que parchearlos después, y
`verificacion_comando` estaba en 0 de 57 fichas.

Este hook se engancha a la escritura DEL LEDGER, no a un comando. Da igual si
el ítem lo cerró `plan-run.sh`, `/arnes-plan:plan-siguiente`, o alguien editando el JSON a
mano: si un ítem acaba de pasar a `hecho`, aquí se comprueba.

Qué comprueba, sólo sobre los ítems que ACABAN de cerrarse (comparando con la
versión del ledger en HEAD, no con todo el fichero: reclamar cosas al trabajo
ya cerrado sería ruido permanente):

  · que dejó `resultado` escrito;
  · que su `verificacion_comando`, si lo tiene, sale 0 corriéndolo aquí;
  · y, sobre el ledger entero pero sólo como aviso, claves fuera del esquema.

Sobre correr un comando desde un hook: sale del ledger del propio proyecto, con
los permisos de quien trabaja, igual que un `Makefile` del repositorio. Si no te
fiarías de eso, el problema no es este hook. Sólo se ejecuta para ítems recién
cerrados y con un límite de tiempo, para que no cuelgue la sesión.

Salida: nada si todo está bien (silencio es aprobación). Si algo falla, escribe
en stdout el motivo, que Claude Code entrega al modelo en el momento exacto de
la infracción — no tres pasos después, cuando el commit ya está escrito.
"""
import json
import os
import subprocess
import sys

# La salida, en UTF-8 y no en lo que decida el sistema. En Windows, Python
# escribe UTF-8 a una consola pero cae al locale —cp1252— cuando su salida va a
# una TUBERÍA, y ahí `✓` no existe: `print` lanzaba UnicodeEncodeError y el
# script salía 1 justo cuando alguien captura su salida para decidir con su
# código de retorno. Se fija la codificación en vez de renunciar a los símbolos.
try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except Exception:      # un flujo sustituido, o un Python sin reconfigure
    pass

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', 'scripts'))

LEDGER_BASENAME = 'ejecucion-plan.estado.json'
HERRAMIENTAS = {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'}
LIMITE_SEG = int(os.environ.get('ARNES_LIMITE_VERIFICACION', '120'))

# El esquema lo define el validador y aquí se importa: dos listas de campos
# conocidos en dos ficheros divergirían, y el aviso empezaría a mentir.
from validar_ledger_compat import CONOCIDAS  # noqa: E402


def salir_callado():
    sys.exit(0)


def texto(valor):
    return str(valor).strip() if valor is not None else ''


def items_de(data):
    for ola in data.get('olas', []):
        for it in ola.get('items', []):
            if isinstance(it, dict) and it.get('id'):
                yield it


def estado_en_head(ruta):
    """El ledger tal como está commiteado. Sirve para saber qué acaba de
    cambiar. Si algo falla —no hay git, el fichero es nuevo— se devuelve None
    y el hook no reclama nada: es preferible callar a inventar un culpable."""
    carpeta = os.path.dirname(ruta) or '.'
    try:
        rel = subprocess.run(['git', '-C', carpeta, 'ls-files', '--full-name', ruta],
                             capture_output=True, text=True, timeout=5)
        nombre = rel.stdout.strip().splitlines()
        if not nombre:
            return None
        previo = subprocess.run(['git', '-C', carpeta, 'show', f'HEAD:{nombre[0]}'],
                                capture_output=True, text=True, timeout=5)
        if previo.returncode != 0:
            return None
        return json.loads(previo.stdout)
    except Exception:
        return None


def correr(comando, cwd):
    try:
        r = subprocess.run(['bash', '-c', comando], cwd=cwd, capture_output=True,
                           text=True, timeout=LIMITE_SEG)
        return r.returncode, (r.stdout + r.stderr)
    except subprocess.TimeoutExpired:
        return None, ''
    except Exception as e:
        return -1, str(e)


def main():
    try:
        entrada = json.load(sys.stdin)
    except Exception:
        salir_callado()

    if entrada.get('tool_name') not in HERRAMIENTAS:
        salir_callado()

    ruta = texto((entrada.get('tool_input') or {}).get('file_path'))
    if not ruta or os.path.basename(ruta) != LEDGER_BASENAME:
        salir_callado()
    if not os.path.isfile(ruta):
        salir_callado()

    try:
        data = json.load(open(ruta, encoding='utf-8'))
    except Exception as e:
        print(f'⚠ El ledger no es JSON válido después de esta edición: {e}\n'
              f'  Arréglalo antes de seguir: el resto del arnés no puede leerlo.')
        sys.exit(0)

    previo = estado_en_head(ruta)
    cerrados_antes = set()
    if previo is not None:
        cerrados_antes = {i['id'] for i in items_de(previo) if i.get('estado') == 'hecho'}

    recien = [i for i in items_de(data)
              if i.get('estado') == 'hecho' and i['id'] not in cerrados_antes]

    quejas = []
    raiz = os.environ.get('CLAUDE_PROJECT_DIR') or os.path.dirname(ruta) or '.'

    for it in recien:
        iid = it['id']
        if not texto(it.get('resultado')):
            quejas.append(
                f'· {iid} pasó a `hecho` sin `resultado`. El estado lo escribe quien hizo\n'
                f'  el trabajo, así que por sí solo no prueba nada: falta qué se hizo y qué\n'
                f'  evidencia lo prueba. Escríbelo, o devuélvelo a `en_curso`.')

        cmd = texto(it.get('verificacion_comando'))
        if cmd:
            codigo, salida = correr(cmd, raiz)
            if codigo is None:
                quejas.append(
                    f'· {iid}: su verificación no terminó en {LIMITE_SEG}s, así que NO está\n'
                    f'  comprobada. Córrela tú: {cmd}')
            elif codigo != 0:
                cola = '\n'.join(salida.strip().splitlines()[-12:])
                quejas.append(
                    f'· {iid} está marcado `hecho` pero su verificación falla (código {codigo}):\n'
                    f'      {cmd}\n'
                    + '\n'.join(f'      {l}' for l in cola.splitlines()))

    # Aviso de deriva: sobre todo el ledger, porque una clave inventada no la
    # arregla quien la escribió sino quien la encuentra, y no bloquea nada.
    desconocidas = {}
    for it in items_de(data):
        for k in it:
            if k not in CONOCIDAS and not k.startswith('_'):
                desconocidas.setdefault(k, []).append(it['id'])
    if desconocidas and recien:
        muestra = sorted(desconocidas)[:8]
        quejas.append(
            f'· Aviso, no bloquea: el ledger usa {len(desconocidas)} campos fuera del esquema '
            f'({", ".join(muestra)}{"…" if len(desconocidas) > 8 else ""}).\n'
            f'  Nadie los valida ni los lee, así que lo que se escriba ahí no lo verá el arnés.\n'
            f'  Si es rastro del cierre, va en `resultado`. Si no, con un `_` delante se ignora.')

    if quejas:
        print('Puerta de cierre del arnés — este cierre no se sostiene todavía:\n')
        print('\n\n'.join(quejas))
    sys.exit(0)


if __name__ == '__main__':
    main()
