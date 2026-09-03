#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Valida un ledger. Sale 0 si está bien, 1 si no, y dice qué falta.

Por qué existe: el ledger lo escriben personas y modelos a mano. Un campo
ausente o un `ola` como string en vez de entero no rompe nada visiblemente —
simplemente hace que /arnes-plan:plan-siguiente elija mal, y eso se descubre
repo ya tuvo ese bug: la Ola 4 tenía su número como string.

Tres niveles de exigencia, y la diferencia importa:

  · Los campos estructurales (CAMPOS_ITEM) se piden a TODO ítem. Sin ellos el
    arnés no sabe ni con qué modelo lanzarlo.
  · `rollback` se pide sólo a los ítems que todavía van a ejecutarse. Es la
    regla que ya dice la plantilla — "si no lo sabes escribir, el ítem no está
    listo para ejecutarse" — y no se puede aplicar hacia atrás: 24 de los 25
    ítems ya cerrados se escribieron antes de que el campo existiera, y
    reclamárselo sería ruido permanente sobre trabajo que ya no se va a tocar.
  · `resultado` se pide a un ítem que ACABA de pasar a `hecho`, y sólo en ese
    momento (`--al-cerrar`). No se reclama en el barrido general por la misma
    razón que `rollback`: los ítems cerrados antes de que la regla existiera no
    se van a volver a tocar. La diferencia es cuándo se comprueba, no qué.

Por qué `resultado` merece una puerta propia: el estado `hecho` lo escribe el
mismo agente que hizo el trabajo, así que por sí solo es autoevaluación. El
campo `resultado` — qué se hizo y qué evidencia lo prueba — es lo único que
deja rastro comprobable por otro, y es justo el que se olvida cuando el ítem
"ya está". Un `hecho` sin `resultado` es un `hecho` optimista con otro nombre.

Un campo presente pero en blanco cuenta como ausente: `"rollback": ""` no es
un plan de reversión, y dejarlo pasar convierte la comprobación en teatro.

Uso:
  python3 validar-ledger.py [ruta]            # todo el ledger
  python3 validar-ledger.py --item 4.2        # antes de ejecutar: ¿está listo?
  python3 validar-ledger.py --al-cerrar 4.2   # después: ¿quedó bien cerrado?
  python3 validar-ledger.py --arreglar-codificacion   # deshace el mojibake
"""
import json, os, sys

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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ledger_path import resolver  # noqa: E402

CAMPOS_OLA = {'ola', 'nombre', 'criterio_de_salida', 'items'}
CAMPOS_ITEM = {'id', 'titulo', 'modelo', 'esfuerzo', 'multiagente',
               'verificacion', 'horas_maquina', 'estado', 'por_que_este_modelo'}
# Se exigen sólo a los ítems que aún se van a ejecutar. Ver el docstring.
CAMPOS_EJECUTABLE = {'rollback'}
EJECUTABLES = {'pendiente', 'en_curso'}
# Se exigen al cerrar, y sólo entonces (--al-cerrar). Ver el docstring.
CAMPOS_CERRADO = {'resultado'}
CERRADOS = {'hecho'}
ESTADOS = {'pendiente', 'en_curso', 'hecho', 'bloqueado', 'descartado'}
MODELOS = {'haiku', 'sonnet', 'opus'}
ESFUERZOS = {'low', 'medium', 'high', 'xhigh', 'max'}

# Esquema de ledger que esta versión del arnés sabe leer. Sólo el mayor manda:
# un menor más alto significa campos añadidos, que un lector viejo ignora sin
# romperse; un mayor más alto significa que algo cambió de forma.
#
# Esto no hacía falta mientras el arnés vivía dentro del proyecto: herramienta
# y ledger viajaban en el mismo commit y no podían desincronizarse. Distribuido
# como plugin sí pueden, y ese es justo el fallo que este campo detecta a
# tiempo en vez de dejar que el arnés elija mal en silencio.
ESQUEMA_SOPORTADO = 1
CLAVE_ESQUEMA = 'schema_version'

# Todo campo que el arnés sabe leer. Lo que no esté aquí es deriva: alguien lo
# inventó en una sesión, nadie lo valida y nadie lo lee — en el consumidor real
# llegaron a 57 nombres fuera de esquema, 50 usados una sola vez, mientras el
# validador respondía "✓ Ledger válido". No es un error, porque el ledger es
# del proyecto; por eso se avisa en vez de fallar. Un `_` delante silencia el
# aviso, que es la vía para notas deliberadas.
CONOCIDAS = set(CAMPOS_ITEM) | CAMPOS_EJECUTABLE | CAMPOS_CERRADO | {
    'verificacion_comando', 'archivos', 'bloquea', 'bloqueado_por', 'origen',
    'commit', 'fecha', 'advertencia_de_coste', 'razon_del_descarte',
}


def revisar_esquema(data, errores):
    """Un ledger sin el campo es anterior a que existiera: se asume 1 y no se
    dice nada. Reclamárselo convertiría en error todos los ledgers en uso."""
    bruto = data.get(CLAVE_ESQUEMA, 1)
    try:
        mayor = int(str(bruto).split('.')[0])
    except (TypeError, ValueError):
        errores.append(f'{CLAVE_ESQUEMA} "{bruto}" no es un número de versión')
        return
    if mayor > ESQUEMA_SOPORTADO:
        errores.append(
            f'El ledger declara {CLAVE_ESQUEMA} {bruto} y este arnés sólo lee '
            f'hasta la {ESQUEMA_SOPORTADO}. Actualiza el plugin '
            f'(`claude plugin update arnes-plan`) antes de tocarlo: leerlo con '
            f'un lector viejo es cómo se corrompe un ledger en silencio.')


def presente(it, campo):
    """Un campo en blanco cuenta como ausente. Los no-texto (bool, número)
    valen por el solo hecho de estar: `horas_maquina: 0` es un valor legítimo
    y `multiagente: false` también, así que aquí no se juzga su verdad."""
    if campo not in it:
        return False
    v = it[campo]
    return bool(str(v).strip()) if isinstance(v, str) else True


def sitio(o, n, m):
    """Etiqueta de posición legible, idéntica por las dos rutas del validador.
    Se prefiere el número de ola al índice de la lista: 'ola 4' es lo que la
    persona ve en el ledger, mientras que 'olas[3]' la obliga a contar. Si el
    número falta o no es entero cae al índice, porque ese caso ES un error que
    se reporta aparte y aquí sólo hace falta poder señalarlo."""
    ola = o.get('ola')
    cabeza = f'ola {ola}' if isinstance(ola, int) else f'olas[{n}]'
    return f'{cabeza}.items[{m}]'


# ── Texto que pasó dos veces por la codificación ────────────────────────────
# Por qué existe: "pólizas" escrito al ledger a través de una consola que lee
# cp1252 lo que ya era UTF-8 queda guardado como "pÃ³lizas" —los dos bytes del
# carácter, leídos como dos caracteres— y ahí se queda para siempre. Nada
# revienta y nada avisa: el JSON sigue siendo UTF-8 válido, el validador sale
# verde, y el mojibake viaja al `resultado`, al visor y al entregable. Se
# descubre cuando alguien lee el dossier terminado, que es el peor momento.
#
# La prueba no es que aparezca una `Ã`: es que el texto REVIERTA. Se vuelve a
# codificar en cp1252 y se lee como UTF-8; si eso da un texto distinto, sólo
# pudo salir de una doble codificación. Un "São Paulo" escrito a propósito no
# revierte —sus bytes en cp1252 no son UTF-8 válido— y no se denuncia.
SOSPECHOSAS = ('\u00c3', '\u00c2')


def revertir(s):
    """El texto sin la vuelta de más, o None si no la llevaba. Itera porque una
    cadena puede haber pasado dos veces por la misma consola."""
    actual = s
    for _ in range(3):
        if not any(c in actual for c in SOSPECHOSAS):
            break
        try:
            siguiente = actual.encode('cp1252').decode('utf-8')
        except (UnicodeEncodeError, UnicodeDecodeError):
            break
        if siguiente == actual:
            break
        actual = siguiente
    return actual if actual != s else None


def codificacion_doble(data):
    """[(donde, texto, revertido)] de todo el ledger. Mira olas e ítems, campo
    a campo: el mismo fallo aparece en el nombre de una ola y en el `resultado`
    de un ítem, y quien lo arregla necesita saber en cuál."""
    hallazgos = []

    def mirar(donde, contenedor):
        for campo, valor in contenedor.items():
            textos = valor if isinstance(valor, list) else [valor]
            for i, t in enumerate(textos):
                if not isinstance(t, str):
                    continue
                limpio = revertir(t)
                if limpio is not None:
                    etiqueta = f'{campo}[{i}]' if isinstance(valor, list) else campo
                    hallazgos.append((f'{donde}.{etiqueta}', t, limpio))

    for n, o in enumerate(data.get('olas', [])):
        if not isinstance(o, dict):
            continue
        ola = o.get('ola')
        mirar(f'ola {ola}' if isinstance(ola, int) else f'olas[{n}]', o)
        for m, it in enumerate(o.get('items') or []):
            if isinstance(it, dict):
                mirar(sitio(o, n, m), it)
    return hallazgos


def arreglar_codificacion(ruta, hallazgos):
    """Deshace la vuelta de más en el fichero. Devuelve cuántos textos cambió,
    o -1 si el resultado no volvía a ser JSON y por tanto no se escribió.

    Se opera sobre el TEXTO del fichero y no sobre el objeto ya parseado: un
    `json.dump` reindentaría el ledger entero y el diff dejaría de decir qué
    cambió de verdad. Un ledger es un fichero versionado que alguien va a leer
    en un `git diff`, y esa legibilidad es media herramienta.
    """
    with open(ruta, encoding='utf-8', newline='') as fh:
        crudo = fh.read()

    # Cada pareja, en las dos formas en que el fichero puede guardarla: el
    # carácter tal cual, o escapado (`\u00f3`) si quien lo escribió usó
    # ensure_ascii. Se pone la que se encuentre, para no cambiarle el estilo.
    parejas = set()
    for _, malo, bueno in hallazgos:
        parejas.add((malo, bueno))
        parejas.add((json.dumps(malo)[1:-1], json.dumps(bueno)[1:-1]))
    # De más largo a más corto: un mojibake puede ser prefijo de otro, y
    # empezar por el corto dejaría el largo a medias.
    nuevo, hechos = crudo, 0
    for malo, bueno in sorted(parejas, key=lambda par: -len(par[0])):
        if malo and malo in nuevo:
            hechos += nuevo.count(malo)
            nuevo = nuevo.replace(malo, bueno)

    if nuevo == crudo:
        return 0
    try:
        json.loads(nuevo)
    except json.JSONDecodeError:
        return -1
    with open(ruta, 'w', encoding='utf-8', newline='') as fh:
        fh.write(nuevo)
    return hechos


def revisar_item(it, donde, errores, ids=None, exigir_cierre=False):
    """Acumula en `errores` los problemas de un ítem. `ids` opcional para
    detectar duplicados cuando se recorre el ledger entero. `exigir_cierre`
    añade los campos que sólo tienen sentido reclamar en el momento de cerrar."""
    iid = it.get('id', 'sin id')
    estado = it.get('estado')

    exigidos = set(CAMPOS_ITEM)
    if estado in EJECUTABLES:
        exigidos |= CAMPOS_EJECUTABLE
    if exigir_cierre and estado in CERRADOS:
        exigidos |= CAMPOS_CERRADO
    faltan = {c for c in exigidos if not presente(it, c)}
    if faltan:
        # Se nombra la razón cuando el campo se exige por el estado: si no, un
        # "falta rollback" sobre un ítem hecho parecería un bug del validador.
        solo_ejecutable = sorted(faltan & CAMPOS_EJECUTABLE)
        solo_cierre = sorted(faltan & CAMPOS_CERRADO)
        estructurales = sorted(faltan - CAMPOS_EJECUTABLE - CAMPOS_CERRADO)
        if estructurales:
            errores.append(f'{donde} ({iid}): faltan campos {estructurales}')
        if solo_ejecutable:
            errores.append(f'{donde} ({iid}): faltan campos {solo_ejecutable} '
                           f'(obligatorios con estado "{estado}": sin plan de '
                           f'reversión escrito, el ítem no está listo para ejecutarse)')
        if solo_cierre:
            errores.append(f'{donde} ({iid}): faltan campos {solo_cierre} '
                           f'(obligatorios al cerrar: un "{estado}" sin qué se hizo '
                           f'y qué evidencia lo prueba no se puede comprobar después)')

    # Se sigue comprobando lo que SÍ está: un campo ausente no debe tapar los
    # otros problemas del mismo ítem. Con un `continue` aquí, un id duplicado
    # pasaba invisible.
    if ids is not None and 'id' in it:
        if iid in ids:
            errores.append(f'{donde}: id duplicado "{iid}" (ya en {ids[iid]})')
        else:
            ids[iid] = donde
    for campo, validos in (('estado', ESTADOS), ('modelo', MODELOS),
                           ('esfuerzo', ESFUERZOS)):
        if campo in it and it[campo] not in validos:
            errores.append(f'{donde} ({iid}): {campo} "{it[campo]}" '
                           f'no es uno de {sorted(validos)}')
    if 'multiagente' in it and not isinstance(it['multiagente'], bool):
        errores.append(f'{donde} ({iid}): multiagente debe ser booleano')
    if 'horas_maquina' in it and not isinstance(it['horas_maquina'], (int, float)):
        errores.append(f'{donde} ({iid}): horas_maquina debe ser un número')


def revisar_bloqueos(orden, errores):
    """Las aristas de `bloqueado_por`, contra el orden del documento.

    El arnés elige el siguiente ítem con una regla lineal —el primero cuyo
    estado sea `pendiente` o `en_curso`— y NO consulta `bloqueado_por` PARA
    ELEGIR: lo consulta después, para decidir si frena, y entonces mira el
    estado del destino y no la presencia del campo. O sea: el ledger no
    planifica, ordena. La posición en el fichero ES el calendario, y
    `bloqueado_por` documenta la arista.

    Esa regla es correcta mientras se cumpla un invariante: toda arista apunta
    hacia atrás. Si un ítem depende de otro que viene después, el arnés propone
    el bloqueado —avisa, pero no lo salta—, y eso es lo que pasa por defecto
    cuando un hallazgo nuevo se añade al final y algo anterior pasa a depender
    de él.

    Se comprueba sólo en los ítems que aún van a ejecutarse, por la misma razón
    que `rollback`: un ítem ya cerrado no se va a mover de sitio, y reclamárselo
    sería ruido permanente.
    """
    posicion = {it['id']: i for i, (it, _) in enumerate(orden) if 'id' in it}
    estado = {it['id']: it.get('estado') for it, _ in orden if 'id' in it}

    for i, (it, donde) in enumerate(orden):
        destino = it.get('bloqueado_por')
        if not destino or not str(destino).strip():
            continue
        iid = it.get('id', '?')
        destino = str(destino).strip()

        if destino not in posicion:
            errores.append(
                f'{donde} ({iid}): bloqueado_por "{destino}" no es el id de '
                f'ningún ítem. Tiene que ser el id literal, no una frase: si '
                f'nadie puede resolverlo, no lo comprueba nadie.')
            continue

        # Sólo para lo que aún va a ejecutarse: mover un ítem cerrado no es
        # una opción, así que exigirle la dirección no arregla nada.
        if it.get('estado') in EJECUTABLES and posicion[destino] > i:
            errores.append(
                f'{donde} ({iid}): bloqueado_por "{destino}" apunta a un ítem '
                f'POSTERIOR. El arnés elige por orden de documento y no lee '
                f'este campo, así que llegaría a {iid} con su bloqueo sin '
                f'cerrar. Mueve {iid} después de {destino}.')
            continue

        if estado.get(destino) in CERRADOS:
            it['_desbloqueado'] = destino


def informar(errores, ruta):
    print(f'✗ {len(errores)} problema(s) en {ruta}:', file=sys.stderr)
    for e in errores:
        print(f'  · {e}', file=sys.stderr)
    return 1


def main():
    args = sys.argv[1:]
    item_pedido, exigir_cierre = None, False
    arreglar = '--arreglar-codificacion' in args
    if arreglar:
        args.remove('--arreglar-codificacion')
    # --item y --al-cerrar miran el mismo ítem en momentos distintos: el
    # primero antes de gastar (¿tiene con qué ejecutarse?), el segundo después
    # (¿dejó rastro de qué pasó?). Comparten camino para no divergir.
    for bandera in ('--item', '--al-cerrar'):
        if bandera in args:
            i = args.index(bandera)
            if i + 1 >= len(args):
                print(f'✗ {bandera} necesita un id (o un prefijo).', file=sys.stderr)
                return 1
            item_pedido = args[i + 1]
            exigir_cierre = bandera == '--al-cerrar'
            del args[i:i + 2]
            break

    ruta = args[0] if args else resolver()
    if not ruta or not os.path.isfile(ruta):
        print('✗ No encuentro el ledger.', file=sys.stderr)
        return 1

    try:
        data = json.load(open(ruta, encoding='utf-8'))
    except json.JSONDecodeError as e:
        print(f'✗ JSON inválido en {ruta}: {e}', file=sys.stderr)
        return 1

    if not isinstance(data.get('olas'), list) or not data['olas']:
        print("✗ Falta la lista 'olas' o está vacía.", file=sys.stderr)
        return 1

    # Antes de validar: un ledger con mojibake es un ledger válido, pero si
    # además le falta un campo, el arreglo del texto no tiene por qué esperar a
    # que se complete la ficha. Son dos problemas distintos.
    if arreglar:
        hallazgos = codificacion_doble(data)
        if not hallazgos:
            print('✓ Nada que arreglar: no hay texto doblemente codificado.')
            return 0
        hechos = arreglar_codificacion(ruta, hallazgos)
        if hechos < 0:
            print('✗ El arreglo no volvía a ser JSON válido. No he escrito nada.',
                  file=sys.stderr)
            return 1
        if hechos == 0:
            print('✗ Detecto el texto pero no lo encuentro en el fichero tal cual.',
                  file=sys.stderr)
            print('   Pasa si algo reescribió el ledger con otra codificación.',
                  file=sys.stderr)
            return 1
        for donde, malo, bueno in hallazgos:
            print(f'  {donde}')
            print(f'    decía: {malo[:70]}')
            print(f'    dice:  {bueno[:70]}')
        print(f'✓ {hechos} texto(s) arreglados en {ruta}.')
        print('  Revisa el `git diff` y commitéalo: el ledger es lo que sobrevive.')
        return 0

    errores = []
    revisar_esquema(data, errores)
    if errores:
        return informar(errores, ruta)

    # ── Un solo ítem: la comprobación que corre antes de gastar ──────────────
    if item_pedido is not None:
        for n, o in enumerate(data['olas']):
            for m, it in enumerate(o['items']):
                if str(it.get('id', '')).startswith(item_pedido):
                    revisar_item(it, sitio(o, n, m), errores,
                                 exigir_cierre=exigir_cierre)
                    if errores:
                        return informar(errores, ruta)
                    if exigir_cierre:
                        if it['estado'] in CERRADOS:
                            print(f'✓ {it["id"]} cerró con rastro de qué pasó.')
                        else:
                            # No es un fallo: un ítem que quedó `bloqueado` o
                            # `en_curso` no cerró, y a eso no se le reclama un
                            # `resultado`. Pero decirlo evita leer el ✓ como
                            # "el ítem está hecho".
                            print(f'✓ {it["id"]} bien formado; su estado es '
                                  f'"{it["estado"]}", así que no cerró.')
                    elif it['estado'] in EJECUTABLES:
                        print(f'✓ {it["id"]} está listo para ejecutarse '
                              f'(estado "{it["estado"]}").')
                    else:
                        # Válido, pero no es lo mismo que estar listo: a un ítem
                        # cerrado no se le pidió rollback, así que no se puede
                        # afirmar que se sabría revertir.
                        print(f'✓ {it["id"]} bien formado, pero su estado es '
                              f'"{it["estado"]}": no es un ítem ejecutable.')
                    return 0
        print(f'✗ Ningún ítem empieza por "{item_pedido}".', file=sys.stderr)
        return 1

    # ── Ledger completo ─────────────────────────────────────────────────────
    ids, numeros, orden = {}, [], []
    for n, o in enumerate(data['olas']):
        donde = f"olas[{n}]"
        faltan = CAMPOS_OLA - set(o)
        if faltan:
            errores.append(f'{donde}: faltan campos {sorted(faltan)}')
            continue
        if not isinstance(o['ola'], int):
            errores.append(f"{donde}: 'ola' es {type(o['ola']).__name__}, "
                           f"debe ser entero (un `ola:N` no emparejaría)")
        numeros.append(o['ola'])
        for m, it in enumerate(o['items']):
            revisar_item(it, sitio(o, n, m), errores, ids)
            orden.append((it, sitio(o, n, m)))

    if len(set(numeros)) != len(numeros):
        errores.append(f'Números de ola repetidos: {numeros}')

    revisar_bloqueos(orden, errores)

    if errores:
        return informar(errores, ruta)

    por_estado = {}
    for o in data['olas']:
        for it in o['items']:
            por_estado[it['estado']] = por_estado.get(it['estado'], 0) + 1
    resumen = ', '.join(f'{v} {k}' for k, v in sorted(por_estado.items()))
    print(f'✓ Ledger válido: {len(data["olas"])} olas, {len(ids)} ítems ({resumen}).')

    # Aviso, no error: no invalida el ledger, pero sin decirlo estos campos se
    # acumulan y lo que se escribe en ellos no lo lee nadie.
    derivadas = sorted({c for o in data['olas'] for it in o['items']
                        for c in it if c not in CONOCIDAS and not c.startswith('_')})
    if derivadas:
        muestra = ', '.join(derivadas[:8]) + ('…' if len(derivadas) > 8 else '')
        print(f'  ⚠ {len(derivadas)} campos fuera del esquema: {muestra}')
        print(f'    El arnés no los lee. Si son rastro del cierre, van en '
              f'`resultado`; con `_` delante se ignoran.')

    # Aviso, no error: el JSON es UTF-8 válido y el ledger no está roto. Pero
    # este texto no lo arregla quien lo escribió —no lo vio— sino quien lo
    # encuentra, y si nadie lo encuentra sale impreso en el entregable.
    dobles = codificacion_doble(data)
    if dobles:
        print(f'  ⚠ {len(dobles)} texto(s) con la codificación pasada dos veces:')
        for donde, malo, bueno in dobles[:3]:
            print(f'    {donde}: {malo[:56]}')
            print(f'      debería decir: {bueno[:56]}')
        if len(dobles) > 3:
            print(f'    …y {len(dobles) - 3} más.')
        print('    Lo escribió una consola que leyó como cp1252 lo que ya era')
        print('    UTF-8. Deshacerlo:  arnes validar --arreglar-codificacion')

    # Informe, no error: que el bloqueo de un ítem haya cerrado es lo que pasa
    # cada vez que se cierra algo. Convertirlo en error haría fallar el ledger
    # en el caso más normal, y un validador que grita cuando todo está bien se
    # deja de leer. Pero sin decirlo, un ítem se queda ejecutable y nadie se
    # entera: el campo no cambia al cerrarse su bloqueante.
    listos = [(it.pop('_desbloqueado'), it['id']) for o in data['olas']
              for it in o['items']
              if '_desbloqueado' in it and it['estado'] in EJECUTABLES]
    if listos:
        print(f'  → {len(listos)} ítem(s) con el bloqueo ya cerrado:')
        for destino, iid in listos:
            print(f'    {iid} esperaba a {destino}, que está hecho.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
