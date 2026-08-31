#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ver.py — La vista web del plan. Una página, generada en local, sin inferencia.

Uso:
  arnes ver                    genera la página y la abre en el navegador
  arnes ver --live             además la sirve y la refresca al cambiar el ledger
  arnes ver --salida ruta.html escribe el archivo donde tú digas
  arnes ver --no-abrir         sólo genera, no abre nada (para CI o scripts)

Por qué existe: hasta ahora la única vista del plan era
/arnes-plan:plan-estado, que gasta una llamada al modelo cada vez para leer un
JSON que ya está en el disco, y contesta con texto que se pierde en el scroll.
El ledger tiene mucho más de lo que ese comando enseña —criterios de entrada y
salida por ola, `resultado` y `rollback` por ítem, horas de máquina, fechas de
cierre— y todo eso es cómputo local: cero tokens, y cada uno lo abre desde su
propio checkout.

Dos decisiones que no son de estilo:

  · La página se renderiza ENTERA aquí y sale autocontenida: sin CDN, sin
    fuentes remotas, sin fetch. Así el archivo se manda por chat y se abre en
    una máquina sin red, que es la mitad de la razón de que exista.

  · El archivo va a un temporal, no al repositorio, y compartirlo se hace DESDE
    la página: los botones "Guardar copia" y "Copiar resumen". Dejar la ruta
    escrita en la consola convierte cada envío en buscar, copiar y adjuntar a
    mano; y escribir dentro del proyecto obliga a decidir si eso se versiona,
    que es una pregunta que nadie pidió. `--salida` sigue existiendo para quien
    quiera el archivo en un sitio concreto.

  · El esquema de ítem es deliberadamente abierto. En un ledger real conviven
    setenta y pico claves distintas y la mayoría aparece una sola vez
    (`hallazgo_no_previsto`, `errores_de_metodo_cometidos`, `escepticismo_n1`),
    y ahí está lo más valioso del registro. Una plantilla rígida las tiraría en
    silencio, que es el peor fallo posible en un visor: no se nota. Aquí las
    claves conocidas se renderizan estructuradas y TODO lo demás se vuelca al
    pie de la tarjeta. Nada se pierde por no estar previsto.

Lo que este visor NO hace, a propósito: dibujar un grafo de dependencias.
`bloquea` y `dependencia` son prosa libre en los ledgers reales ("Bloquea toda
medición de recall de las olas 5 y 6: ..."), no listas de ids. Sólo
`bloqueado_por` lleva un id, y sólo cuando ese id existe se convierte en
enlace. Un grafo inventado a base de adivinar ids dentro de un párrafo sería
más bonito y menos cierto. Lo único que sí se deduce de la arista es si sigue
viva: el destino cerrado se marca, porque nadie limpia el campo al cerrarlo.
"""
import argparse
import hashlib
import html
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from ledger_path import resolver, raiz  # noqa: E402

# ── Vocabulario del ledger ──────────────────────────────────────────────────
# El orden es el de lectura de una tarjeta: primero de dónde sale el ítem, luego
# cómo se comprueba, luego qué pasó y cómo se deshace. Una clave que no esté
# aquí no se pierde: cae en "otras notas" al final de la tarjeta.
ESTADOS = ('en_curso', 'pendiente', 'bloqueado', 'hecho', 'descartado')
# En una barra de avance el orden no es el del vocabulario: es el del progreso.
# Con `hecho` al final, una ola con un bloqueado pintaba el rojo a la izquierda
# y parecía que el trabajo iba hacia atrás.
ORDEN_BARRA = ('hecho', 'en_curso', 'pendiente', 'bloqueado', 'descartado')
ETIQUETA_ESTADO = {
    'en_curso': 'en curso', 'pendiente': 'pendiente', 'bloqueado': 'bloqueado',
    'hecho': 'hecho', 'descartado': 'descartado', 'sin_estado': 'sin estado',
}

DETALLE = [
    ('origen', 'De dónde sale'),
    ('contexto', 'Contexto'),
    ('verificacion', 'Cómo se verifica'),
    ('verificacion_comando', 'Comando de verificación'),
    ('verificacion_real', 'Verificación real'),
    ('criterio_de_aceptacion_adicional', 'Criterio de aceptación adicional'),
    ('resultado', 'Qué se hizo'),
    ('medicion_final', 'Medición final'),
    ('numeros', 'Números'),
    ('evidencia', 'Evidencia'),
    ('evidencia_directa', 'Evidencia directa'),
    ('archivos', 'Archivos'),
    ('commit', 'Commit'),
    ('rollback', 'Cómo se revierte'),
    ('bloqueado_por', 'Bloqueado por'),
    ('bloquea', 'Bloquea'),
    ('dependencia', 'Dependencia'),
    ('razon_bloqueo', 'Razón del bloqueo'),
    ('razon_del_descarte', 'Razón del descarte'),
    ('consecuencia_si_no', 'Consecuencia si no se hace'),
    ('advertencia_de_coste', 'Advertencia de coste'),
    ('por_que_este_modelo', 'Por qué este modelo'),
    ('por_que_multiagente', 'Por qué multiagente'),
]
# Ya salen en la cabecera de la tarjeta; repetirlas abajo sería ruido.
EN_CABECERA = {'id', 'titulo', 'estado', 'modelo', 'esfuerzo', 'horas_maquina',
               'multiagente', 'fecha', 'fecha_inicio', 'fecha_cierre'}

# Claves de nivel ola que se pintan aparte, no como ítem.
CABECERA_OLA = {'ola', 'nombre', 'items'}


def e(texto):
    """Escapa para HTML. Todo lo que venga del ledger pasa por aquí."""
    return html.escape(str(texto), quote=True)


def bonita(clave):
    """`hallazgo_no_previsto` → `Hallazgo no previsto`."""
    t = str(clave).lstrip('_').replace('_', ' ').strip()
    return t[:1].upper() + t[1:] if t else str(clave)


def horas(n):
    """0 → '—', 0.5 → '30 min', 18.5 → '18,5 h'. La coma es deliberada."""
    try:
        n = float(n)
    except (TypeError, ValueError):
        return '—'
    if n == 0:
        return '—'
    if n < 1:
        return '%d min' % round(n * 60)
    return ('%g' % round(n, 2)).replace('.', ',') + ' h'


# ── Lectura y agregados ─────────────────────────────────────────────────────
def leer(ruta):
    with open(ruta, encoding='utf-8') as fh:
        return json.load(fh)


def elegir_siguiente(olas):
    """El ítem que tomaría `arnes`.

    La regla que manda es la de plan-run.sh (la selección de su bloque de
    Python): el PRIMERO en orden de documento cuyo estado sea `pendiente` o
    `en_curso`. Se copia esa y no la de plan-siguiente-linea.py, que antepone
    cualquier `en_curso` a cualquier `pendiente`: las dos existen y discrepan de
    verdad —con 1.1 pendiente y 1.2 en curso, la línea del arranque anuncia 1.2
    y el lanzador ejecuta 1.1—, así que aquí se enseña la del que ejecuta. Un
    `en_curso` que se quede fuera no se pierde: lo avisa `a_medias()`.
    """
    for o in olas:
        for it in o.get('items', []):
            if it.get('estado') in ('pendiente', 'en_curso'):
                return it, o
    return None, None


def a_medias(olas, elegido):
    """Ítems `en_curso` que NO son el elegido: trabajo abierto que el lanzador
    no va a retomar por su cuenta. Sin este aviso quedan huérfanos — el ledger
    los tiene abiertos y nada vuelve a mencionarlos."""
    fuera = []
    for o in olas:
        for it in o.get('items', []):
            if it.get('estado') == 'en_curso' and it is not elegido:
                fuera.append((it, o))
    return fuera


def resumen(olas):
    """Los números de cabecera. `descartado` no cuenta como trabajo pendiente
    ni como trabajo hecho: sale aparte para que el porcentaje no mienta."""
    cuenta = dict((s, 0) for s in ESTADOS)
    cuenta['sin_estado'] = 0
    h_hechas = h_por_delante = 0.0
    for o in olas:
        for it in o.get('items', []):
            est = it.get('estado') or 'sin_estado'
            cuenta[est] = cuenta.get(est, 0) + 1
            try:
                hm = float(it.get('horas_maquina') or 0)
            except (TypeError, ValueError):
                hm = 0.0
            if est == 'hecho':
                h_hechas += hm
            elif est != 'descartado':
                h_por_delante += hm
    total = sum(cuenta.values())
    contables = total - cuenta.get('descartado', 0)
    return {
        'cuenta': cuenta, 'total': total, 'contables': contables,
        'pct': (100.0 * cuenta.get('hecho', 0) / contables) if contables else 0.0,
        'horas_hechas': h_hechas, 'horas_por_delante': h_por_delante,
    }


def avisos_del_validador(ledger):
    """Lo que se queja `validar-ledger.py`, si se queja.

    Se delega en él en vez de reimplementar las reglas: si mañana se añade una
    comprobación, esta página la hereda sin tocarla. Si el validador no está o
    revienta, la página sale igual — un visor no puede depender de eso.
    """
    guion = os.path.join(AQUI, 'validar-ledger.py')
    if not os.path.isfile(guion):
        return None
    try:
        r = subprocess.run([sys.executable, guion, ledger],
                           capture_output=True, text=True, timeout=60)
    except Exception:
        return None
    if r.returncode == 0:
        return None
    return ((r.stdout or '') + (r.stderr or '')).strip() or None


def cronologia(olas):
    """Ítems cerrados por fecha, en orden. Es el único avance medido y no
    estimado que hay en el ledger: la fecha la escribió el cierre del ítem."""
    por_dia = {}
    for o in olas:
        for it in o.get('items', []):
            if it.get('estado') != 'hecho':
                continue
            f = it.get('fecha_cierre') or it.get('fecha')
            if not f:
                continue
            por_dia.setdefault(str(f)[:10], []).append(it)
    return sorted(por_dia.items())


# ── Render ──────────────────────────────────────────────────────────────────
# Notas de diseño, porque no son de gusto:
#
#  · Esto no es un documento que se lea de arriba abajo: es un tablero que se
#    escanea. Así que primero el resumen y "qué toca ahora", y sólo después el
#    detalle; y el estado se codifica en forma —punto, palabra, franja— además
#    de en color, para que se lea de un vistazo y también sin distinguir el
#    color.
#
#  · La paleta de estados pasó el validador de la guía de visualización en los
#    dos temas (banda de luminosidad, croma, separación para daltonismo y
#    contraste sobre la superficie). `pendiente` no es un color de serie: es la
#    pista sin rellenar de la barra, y por eso es neutro a propósito.
#    La separación bajo tritanopía queda por debajo del suelo recomendado, lo
#    que obliga a codificación secundaria — la hay en todas partes: cada
#    segmento lleva su cuenta en el título, cada barra su fracción al lado,
#    cada tarjeta la palabra del estado, y los segmentos van separados por un
#    hueco de 2 px.
#
#  · Sin fuentes remotas. La página tiene que abrirse en una máquina sin red,
#    así que la personalidad tipográfica sale de la escala, el peso y el
#    interletrado sobre las familias que ya tiene el sistema — no de un enlace
#    a un servidor de fuentes que aquí no cargaría.

ORDEN_BARRA_LEYENDA = (('hecho', 'hecho'), ('en_curso', 'en curso'),
                       ('pendiente', 'pendiente'), ('bloqueado', 'bloqueado'))


def valor_html(v, ids_conocidos=(), enlazar=False):
    """Un valor del ledger, sea lo que sea. Listas y dicts también: el esquema
    es abierto y un `str(v)` de un dict en pantalla es basura ilegible."""
    if isinstance(v, bool):
        return '<span class="bool">%s</span>' % ('sí' if v else 'no')
    if isinstance(v, (list, tuple)):
        return '<ul class="lista">%s</ul>' % ''.join(
            '<li>%s</li>' % valor_html(x, ids_conocidos) for x in v)
    if isinstance(v, dict):
        return '<dl class="anidado">%s</dl>' % ''.join(
            '<dt>%s</dt><dd>%s</dd>' % (e(bonita(k)), valor_html(x, ids_conocidos))
            for k, x in v.items())
    txt = str(v)
    if enlazar and txt.strip() in ids_conocidos:
        return '<a class="ref" href="#it-%s">%s</a>' % (e(slug(txt.strip())), e(txt))
    return e(txt)


def slug(id_item):
    return ''.join(c if (c.isalnum() or c in '-_') else '-' for c in str(id_item))


def punto(est):
    """El estado nunca va sólo en color: punto + palabra, siempre juntos."""
    return '<span class="punto e-%s" aria-hidden="true"></span>' % e(est)


def tarjeta(it, ids_conocidos):
    est = it.get('estado') or 'sin_estado'
    idi = it.get('id', '(sin id)')
    P = []
    A = P.append
    A('<article class="item e-%s" id="it-%s" data-estado="%s" data-busca="%s">' % (
        e(est), e(slug(idi)), e(est),
        e((str(idi) + ' ' + str(it.get('titulo', ''))).lower())))
    A('<div class="item-cab">')
    A('<span class="estado e-%s">%s%s</span>' % (
        e(est), punto(est), e(ETIQUETA_ESTADO.get(est, est))))
    # El id es un enlace a sí mismo: así se manda "mira el 4.3" sin explicar
    # dónde está.
    A('<a class="id" href="#it-%s" title="Enlace directo a este ítem">%s</a>'
      % (e(slug(idi)), e(idi)))
    A('<h3>%s</h3>' % e(it.get('titulo', '')))
    A('</div>')

    # Fila de coste: es lo que se mira antes de decidir si se lanza ahora.
    meta = []
    if it.get('modelo'):
        meta.append('<span class="chip dato">%s%s</span>' % (
            e(it['modelo']), '/' + e(it['esfuerzo']) if it.get('esfuerzo') else ''))
    if it.get('horas_maquina'):
        meta.append('<span class="chip coste">%s de máquina</span>' % e(horas(it['horas_maquina'])))
    if it.get('multiagente'):
        meta.append('<span class="chip ojo">multiagente</span>')
    for k in ('fecha_inicio', 'fecha', 'fecha_cierre'):
        if it.get(k):
            meta.append('<span class="chip">%s %s</span>' % (e(bonita(k).lower()), e(it[k])))
    if meta:
        A('<div class="meta">%s</div>' % ''.join(meta))

    cuerpo = []
    for clave, etiqueta in DETALLE:
        if clave in it and it[clave] not in (None, '', [], {}):
            valor = valor_html(it[clave], ids_conocidos,
                               enlazar=(clave == 'bloqueado_por'))
            # El campo no se limpia cuando el bloqueante cierra, así que sin esta
            # marca la ficha de un ítem perfectamente ejecutable sigue diciendo
            # "Bloqueado por" para siempre. Se marca, no se oculta: la arista es
            # cierta y su historia importa; lo que cambió es que ya no frena.
            if (clave == 'bloqueado_por'
                    and isinstance(ids_conocidos, dict)
                    and ids_conocidos.get(str(it[clave]).strip()) == 'hecho'):
                valor += ' <span class="chip">ya cerrado: no bloquea</span>'
            cuerpo.append('<div class="campo c-%s"><dt>%s</dt><dd>%s</dd></div>'
                          % (e(clave), e(etiqueta), valor))

    # Todo lo que el esquema no previó. Ver el docstring: esto es el punto.
    conocidas = EN_CABECERA | set(k for k, _ in DETALLE)
    otras = [(k, v) for k, v in it.items()
             if k not in conocidas and v not in (None, '', [], {})]
    if otras:
        cuerpo.append('<div class="campo otras"><dt>Otras notas del ledger</dt><dd>%s</dd></div>'
                      % ''.join('<div class="nota"><b>%s</b> %s</div>' % (
                          e(bonita(k)), valor_html(v, ids_conocidos)) for k, v in otras))
    if cuerpo:
        A('<dl class="detalle">%s</dl>' % ''.join(cuerpo))
    A('</article>')
    return ''.join(P)


def barra(items, con_etiqueta=True):
    """La barra apilada de una ola. Hueco de 2 px entre segmentos —si se tocan,
    dos estados contiguos parecen uno— y un mínimo de ancho para que un solo
    ítem bloqueado entre veinte no desaparezca."""
    n = len(items) or 1
    cuentas = [(est, sum(1 for i in items if (i.get('estado') or 'sin_estado') == est))
               for est in ORDEN_BARRA]
    segs = []
    for est, c in cuentas:
        if c:
            segs.append('<span class="seg e-%s" style="flex:%d 0 auto" title="%d %s"></span>'
                        % (e(est), c, c, e(ETIQUETA_ESTADO[est])))
    etiqueta = ' · '.join('%d %s' % (c, ETIQUETA_ESTADO[est]) for est, c in cuentas if c)
    return ('<div class="barra"%s>%s</div>'
            % (' role="img" aria-label="%s"' % e(etiqueta) if con_etiqueta else '',
               ''.join(segs)))


def crono_html(crono):
    """Ítems cerrados por día. Una serie, así que no lleva leyenda: la etiqueta
    la pone el título. Sólo se rotulan el día más alto y el último —un número
    sobre cada barra es ruido— y los datos van además en una tabla, que es lo
    que hace la vista utilizable con lector de pantalla."""
    if not crono:
        return ''
    alto = max(len(v) for _, v in crono) or 1
    total = sum(len(v) for _, v in crono)
    cols = []
    for idx, (dia, its) in enumerate(crono):
        n = len(its)
        rotulo = ''
        if n == alto or idx == len(crono) - 1:
            rotulo = '<span class="valor">%d</span>' % n
        cols.append(
            '<div class="col"><span class="tallo" style="height:%.1f%%">%s</span>'
            '<span class="dia">%s</span>'
            '<span class="tip"><b>%s</b><br>%d ítem%s: %s</span></div>'
            % (100.0 * n / alto, rotulo, e(dia[5:]), e(dia), n, '' if n == 1 else 's',
               e(', '.join(str(i.get('id', '')) for i in its))))
    filas = ''.join('<tr><td>%s</td><td class="num">%d</td><td>%s</td></tr>'
                    % (e(dia), len(its),
                       e(', '.join(str(i.get('id', '')) for i in its)))
                    for dia, its in crono)
    return (
        '<section class="crono" aria-labelledby="t-crono">'
        '<h2 id="t-crono">Cuándo se cerró cada cosa</h2>'
        '<p class="ayuda">%d ítems cerrados en %d días de trabajo. Sale del campo '
        '<code>fecha</code> de cada ítem: es avance medido, no estimado.</p>'
        '<div class="grafico" role="img" aria-label="Ítems cerrados por día, de %s a %s; '
        'máximo %d en un día.">%s</div>'
        '<details class="tabla"><summary>Ver los datos como tabla</summary>'
        '<div class="scroll"><table><thead><tr><th>Día</th><th class="num">Cerrados</th>'
        '<th>Ítems</th></tr></thead><tbody>%s</tbody></table></div></details>'
        '</section>'
        % (total, len(crono), e(crono[0][0]), e(crono[-1][0]), alto, ''.join(cols), filas))


def generar(ledger_ruta, version='?', proyecto=None):
    datos = leer(ledger_ruta)
    olas = datos.get('olas')
    if not isinstance(olas, list):
        raise ValueError('El ledger no tiene una lista `olas`: %s' % ledger_ruta)

    r = resumen(olas)
    sig, sig_ola = elegir_siguiente(olas)
    avisos = avisos_del_validador(ledger_ruta)
    # id -> estado, no un conjunto de ids: `bloqueado_por` necesita saber si su
    # destino sigue abierto para no pintar como bloqueo uno que ya cerró.
    ids = {str(i.get('id')): i.get('estado')
           for o in olas for i in o.get('items', []) if i.get('id')}
    proyecto = proyecto or raiz()
    nombre = os.path.basename(proyecto.rstrip('/')) or 'proyecto'
    ahora = datetime.now().strftime('%Y-%m-%d %H:%M')
    c = r['cuenta']

    P = []
    A = P.append

    # ── Identidad y acciones ────────────────────────────────────────────────
    A('<header class="cabecera"><div class="ancho">')
    A('<p class="micro">Plan de ingeniería</p>')
    A('<h1>%s</h1>' % e(nombre))
    A('<p class="sello">%s · generado el %s · arnés v%s · sin inferencia</p>' % (
        e(os.path.relpath(ledger_ruta, proyecto) if ledger_ruta.startswith(proyecto)
          else ledger_ruta), e(ahora), e(version)))
    # Compartir se hace desde aquí, no copiando una ruta de la consola.
    A('<div class="acciones">'
      '<button id="btn-guardar" type="button" class="primario">Guardar copia</button>'
      '<button id="btn-resumen" type="button">Copiar resumen</button>'
      '<button id="btn-pdf" type="button">Imprimir o PDF</button>'
      '<span id="aviso" class="aviso" role="status" aria-live="polite"></span>'
      '</div>')
    A('<p class="ayuda">«Guardar copia» descarga esta misma página en un solo archivo, '
      'lista para adjuntar. «Copiar resumen» deja el estado en texto en el portapapeles.</p>')
    A('</div></header>')

    A('<main class="ancho" id="principal">')

    # ── Lo que toca ahora, con los números al lado ──────────────────────────
    A('<section class="panel" aria-labelledby="t-estado"><h2 id="t-estado" class="oculta">Estado</h2>')
    A('<div class="rejilla-panel">')

    if sig:
        clase = 'en-curso' if sig.get('estado') == 'en_curso' else ''
        A('<div class="ahora %s">' % clase)
        A('<p class="micro">%s</p>' % (
            'Quedó a medias — se retoma antes que ningún otro'
            if sig.get('estado') == 'en_curso' else 'Lo siguiente que toca'))
        A('<a class="titulo" href="#it-%s"><span class="id">%s</span>%s</a>' % (
            e(slug(sig.get('id', ''))), e(sig.get('id', '')), e(sig.get('titulo', ''))))
        A('<p class="donde">Ola %s · %s</p>' % (e(sig_ola.get('ola', '?')),
                                                e(sig_ola.get('nombre', ''))))
        det = []
        if sig.get('modelo'):
            det.append('<span class="chip dato">%s/%s</span>'
                       % (e(sig['modelo']), e(sig.get('esfuerzo', ''))))
        if sig.get('horas_maquina'):
            det.append('<span class="chip coste">%s de máquina</span>'
                       % e(horas(sig['horas_maquina'])))
        if sig.get('multiagente'):
            det.append('<span class="chip ojo">multiagente</span>')
        if det:
            A('<div class="meta">%s</div>' % ''.join(det))
        A('<p class="lanzar">Se lanza con <code>arnes</code> en una sesión limpia, '
          'o con <code>/arnes-plan:plan-siguiente</code>.</p>')
        A('</div>')
    else:
        A('<div class="ahora completo"><p class="micro">No queda nada pendiente</p>'
          '<p class="donde">Todos los ítems del ledger están cerrados o descartados.</p></div>')

    abiertos = a_medias(olas, sig)
    if abiertos:
        A('<div class="abiertos"><p class="micro">Quedaron a medias y nadie los va a retomar solo</p>')
        for it, o in abiertos:
            A('<a href="#it-%s"><code>%s</code> %s</a>'
              % (e(slug(it.get('id', ''))), e(it.get('id', '')), e(it.get('titulo', ''))))
        A('<p class="pista-abiertos">`arnes` toma el primero por orden de documento, '
          'así que estos no salen por su turno. Se lanzan por id: '
          '<code>arnes %s</code>.</p>' % e(abiertos[0][0].get('id', '')))
        A('</div>')

    A('<div class="kpis">')
    A('<div class="kpi"><b>%d<span class="unidad">%%</span></b>'
      '<span class="et">cerrado</span><small>%d de %d ítems</small>'
      '<div class="barra fina"><span class="seg e-hecho" style="width:%.4f%%"></span></div></div>'
      % (round(r['pct']), c.get('hecho', 0), r['contables'], r['pct']))
    por_delante = c.get('pendiente', 0) + c.get('en_curso', 0) + c.get('bloqueado', 0)
    A('<div class="kpi"><b>%d</b><span class="et">por delante</span>'
      '<small>%d pendientes · %d en curso · %d bloqueados</small></div>'
      % (por_delante, c.get('pendiente', 0), c.get('en_curso', 0), c.get('bloqueado', 0)))
    A('<div class="kpi"><b>%s</b><span class="et">de máquina por delante</span>'
      '<small>%s ya consumidas%s</small></div>'
      % (e(horas(r['horas_por_delante'])), e(horas(r['horas_hechas'])),
         ' · %d descartados' % c['descartado'] if c.get('descartado') else ''))
    A('</div>')
    A('</div>')

    if avisos:
        A('<details class="avisos"><summary><span class="punto e-bloqueado" aria-hidden="true">'
          '</span>El validador del ledger tiene algo que decir</summary>'
          '<div class="scroll"><pre>%s</pre></div>'
          '<p class="ayuda">Sale de <code>validar-ledger.py</code>. No impide trabajar, '
          'pero puede hacer que el arnés elija mal el siguiente ítem.</p></details>' % e(avisos))
    A('</section>')

    # ── Mapa de olas ────────────────────────────────────────────────────────
    A('<section class="mapa" aria-labelledby="t-olas"><h2 id="t-olas">Las olas de un vistazo</h2>')
    A('<div class="filas">')
    for o in olas:
        items = o.get('items', [])
        hechos = sum(1 for i in items if i.get('estado') == 'hecho')
        pend_h = 0.0
        for i in items:
            if i.get('estado') not in ('hecho', 'descartado'):
                try:
                    pend_h += float(i.get('horas_maquina') or 0)
                except (TypeError, ValueError):
                    pass
        A('<a class="fila" href="#ola-%s">'
          '<span class="n">Ola %s</span><span class="nom">%s</span>%s'
          '<span class="frac">%d/%d</span><span class="hs">%s</span></a>'
          % (e(o.get('ola', '?')), e(o.get('ola', '?')), e(o.get('nombre', '')),
             barra(items), hechos, len(items),
             e(horas(pend_h)) if pend_h else '<span class="nada">—</span>'))
    A('</div>')
    A('<p class="ayuda">La última columna son las horas de máquina que quedan por gastar '
      'en cada ola.</p>')
    A('</section>')

    # ── Barra de control ────────────────────────────────────────────────────
    A('<div class="barra-control" role="search">')
    A('<label class="busca"><span class="oculta">Buscar un ítem</span>'
      '<input type="search" id="q" placeholder="Buscar por id o título…" autocomplete="off"></label>')
    A('<div class="segmentos" role="group" aria-label="Filtrar por estado">')
    A('<button class="f activo" type="button" data-f="todo" aria-pressed="true">'
      'todo <b>%d</b></button>' % r['total'])
    for est in ORDEN_BARRA:
        if c.get(est):
            A('<button class="f" type="button" data-f="%s" aria-pressed="false">%s%s <b>%d</b></button>'
              % (e(est), punto(est), e(ETIQUETA_ESTADO[est]), c[est]))
    A('</div>')
    A('<p class="cuenta" id="cuenta" role="status" aria-live="polite"></p>')
    A('</div>')

    # ── Olas e ítems ────────────────────────────────────────────────────────
    for o in olas:
        items = o.get('items', [])
        A('<section class="ola" id="ola-%s" aria-labelledby="t-ola-%s">'
          % (e(o.get('ola', '?')), e(o.get('ola', '?'))))
        hechos_ola = sum(1 for i in items if i.get('estado') == 'hecho')
        A('<div class="ola-cab"><h2 id="t-ola-%s"><span class="n">Ola %s</span>%s'
          '<span class="frac">%d/%d</span></h2>%s</div>'
          % (e(o.get('ola', '?')), e(o.get('ola', '?')), e(o.get('nombre', '')),
             hechos_ola, len(items), barra(items)))
        # Criterios y advertencias: las puertas de la ola. Van arriba porque son
        # lo que decide si esta ola se puede siquiera empezar.
        criterios = [(k, v) for k, v in o.items()
                     if k not in CABECERA_OLA and v not in (None, '', [], {})]
        if criterios:
            A('<dl class="criterios">')
            for k, v in criterios:
                A('<div class="campo c-%s"><dt>%s</dt><dd>%s</dd></div>'
                  % (e(k), e(bonita(k)), valor_html(v, ids)))
            A('</dl>')
        A('<div class="items">')
        for it in items:
            A(tarjeta(it, ids))
        A('</div></section>')

    A(crono_html(cronologia(olas)))

    # ── Notas de cabecera del ledger ────────────────────────────────────────
    notas = [(k, v) for k, v in datos.items() if k != 'olas' and v not in (None, '', [], {})]
    if notas:
        A('<section class="notas" aria-labelledby="t-notas">'
          '<h2 id="t-notas">Notas del ledger</h2><dl>')
        for k, v in notas:
            A('<div class="campo"><dt>%s</dt><dd>%s</dd></div>'
              % (e(bonita(k)), valor_html(v, ids)))
        A('</dl></section>')

    A('</main>')
    A('<footer class="pie-pag"><div class="ancho">Generada por <code>arnes ver</code> '
      'desde <code>%s</code>. Se regenera volviendo a ejecutarlo; no se edita a mano.'
      '</div></footer>' % e(os.path.basename(ledger_ruta)))
    A('<!--VIVO-->')

    return PLANTILLA % {
        'titulo': e('Plan · %s' % nombre),
        'css': CSS,
        'cuerpo': ''.join(P),
        'js': (JS.replace('__RESUMEN__',
                          json.dumps(resumen_en_texto(datos, olas, r, sig, sig_ola,
                                                      nombre, ahora, version)))
                 .replace('__ARCHIVO__',
                          json.dumps('plan-%s-%s.html' % (slug(nombre),
                                                          datetime.now().strftime('%Y%m%d'))))),
    }


def resumen_en_texto(datos, olas, r, sig, sig_ola, nombre, ahora, version):
    """El mismo estado, en texto pegable. Existe porque la mitad de las veces lo
    que hace falta no es la página entera: es contestar "¿cómo vamos?" en un
    chat sin obligar a nadie a abrir un adjunto."""
    L = ['# Plan de ingeniería — %s' % nombre,
         'Estado al %s (arnés v%s, generado desde el ledger).' % (ahora, version), '']
    c = r['cuenta']
    L.append('%d de %d ítems cerrados (%d%%) · %d pendientes · %d en curso · %d bloqueados%s'
             % (c.get('hecho', 0), r['contables'], round(r['pct']), c.get('pendiente', 0),
                c.get('en_curso', 0), c.get('bloqueado', 0),
                ' · %d descartados' % c['descartado'] if c.get('descartado') else ''))
    L.append('Horas de máquina: %s consumidas · %s por delante'
             % (horas(r['horas_hechas']), horas(r['horas_por_delante'])))
    L.append('')
    if sig:
        L.append('Siguiente: %s — %s' % (sig.get('id', ''),
                                         ' '.join(str(sig.get('titulo', '')).split())))
        L.append('  Ola %s: %s · %s/%s · %s de máquina'
                 % (sig_ola.get('ola', '?'), sig_ola.get('nombre', ''), sig.get('modelo', '?'),
                    sig.get('esfuerzo', '?'), horas(sig.get('horas_maquina'))))
    else:
        L.append('No queda ningún ítem pendiente.')
    L.append('')
    for o in olas:
        items = o.get('items', [])
        hechos = sum(1 for i in items if i.get('estado') == 'hecho')
        pend = [i for i in items if i.get('estado') in ('pendiente', 'en_curso', 'bloqueado')]
        L.append('Ola %s — %s: %d/%d' % (o.get('ola', '?'), o.get('nombre', ''),
                                         hechos, len(items)))
        for i in pend:
            L.append('  · [%s] %s — %s' % (i.get('estado', '?'), i.get('id', ''),
                                           ' '.join(str(i.get('titulo', '')).split())[:90]))
    return '\n'.join(L)


# ── La página ───────────────────────────────────────────────────────────────
# Todo inline y sin una sola petición al exterior: el archivo tiene que abrirse
# desde file:// en una máquina sin red. Ver el docstring.
PLANTILLA = """<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>%(titulo)s</title>
<style>%(css)s</style>
</head><body>
<a class="saltar" href="#principal">Saltar al contenido</a>
%(cuerpo)s
<script>%(js)s</script>
</body></html>
"""

CSS = """
/* ── Fichas de color ──────────────────────────────────────────────────────
   Los neutros van sesgados a cálido, del lado del acento, para que no lean a
   gris de plantilla. El acento es ocre de arnés y aparece poco a propósito:
   marca lo que toca hacer, el foco y los enlaces, nada más. El color de
   estado es otra familia y no se mezcla con él. */
:root{
  --fondo:#f6f5f2; --papel:#fff; --hundido:#faf9f6;
  --tinta:#17181b; --tinta-2:#43413d; --tenue:#6f6b64;
  --linea:#e4e0d9; --linea-2:#efece6;
  --acento:#b45309; --acento-tinta:#8a3f07;
  --hecho:#157f4a; --curso:#1d5fd1; --bloq:#b3261e;
  --pista:#d7d3ca; --desc:#b5b0a7;
  --sombra:0 1px 1px rgba(28,25,20,.04), 0 6px 18px -10px rgba(28,25,20,.18);
  --f-texto:-apple-system,BlinkMacSystemFont,"Segoe UI Variable Text","Segoe UI",
    Roboto,Ubuntu,Cantarell,"Helvetica Neue",Arial,sans-serif;
  --f-datos:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,
    "Liberation Mono",monospace;
  --r:10px;
}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){
  --fondo:#16161a; --papel:#1e1f23; --hundido:#191a1e;
  --tinta:#edebe6; --tinta-2:#c3c0b9; --tenue:#98938a;
  --linea:#2e2f34; --linea-2:#26272b;
  --acento:#e59a4a; --acento-tinta:#f0ac66;
  --hecho:#38a76c; --curso:#5b90e3; --bloq:#dc6a63;
  --pista:#3a3b40; --desc:#55565b;
  --sombra:0 1px 1px rgba(0,0,0,.4), 0 8px 22px -12px rgba(0,0,0,.6);
}}
:root[data-theme=dark]{
  --fondo:#16161a; --papel:#1e1f23; --hundido:#191a1e;
  --tinta:#edebe6; --tinta-2:#c3c0b9; --tenue:#98938a;
  --linea:#2e2f34; --linea-2:#26272b;
  --acento:#e59a4a; --acento-tinta:#f0ac66;
  --hecho:#38a76c; --curso:#5b90e3; --bloq:#dc6a63;
  --pista:#3a3b40; --desc:#55565b;
  --sombra:0 1px 1px rgba(0,0,0,.4), 0 8px 22px -12px rgba(0,0,0,.6);
}

*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--fondo);color:var(--tinta);
  font:15px/1.55 var(--f-texto);-webkit-font-smoothing:antialiased;
  font-variant-numeric:tabular-nums}
.ancho{max-width:1120px;margin:0 auto;padding:0 28px}
h1,h2,h3{margin:0;font-weight:640;letter-spacing:-.014em;text-wrap:balance}
p{margin:0}
code{font-family:var(--f-datos);font-size:.86em}
a{color:inherit}
:focus-visible{outline:2px solid var(--acento);outline-offset:2px;border-radius:4px}
.oculta{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);
  white-space:nowrap}
.saltar{position:absolute;left:-9999px;top:8px;background:var(--papel);color:var(--tinta);
  padding:9px 14px;border-radius:var(--r);border:1px solid var(--linea);z-index:99}
.saltar:focus{left:28px}
.scroll{overflow-x:auto}
.micro{font-size:11.5px;text-transform:uppercase;letter-spacing:.09em;font-weight:650;
  color:var(--tenue)}
.ayuda{color:var(--tenue);font-size:12.5px;margin-top:10px;max-width:68ch}

/* ── Cabecera ─────────────────────────────────────────────────────────── */
.cabecera{background:var(--papel);border-bottom:1px solid var(--linea);
  padding:34px 0 26px}
.cabecera h1{font-size:29px;margin-top:7px}
.sello{margin-top:7px;color:var(--tenue);font-size:12.5px;font-family:var(--f-datos)}
.acciones{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:20px}
.acciones button{font:inherit;font-size:13px;padding:8px 15px;border-radius:8px;
  cursor:pointer;border:1px solid var(--linea);background:var(--papel);color:var(--tinta);
  transition:border-color .12s,background .12s}
.acciones button:hover{border-color:var(--tenue)}
.acciones button.primario{background:var(--tinta);color:var(--papel);border-color:var(--tinta)}
.acciones button.primario:hover{background:var(--tinta-2);border-color:var(--tinta-2)}
.aviso{font-size:12.5px;color:var(--hecho);opacity:0;transition:opacity .18s}
.aviso.visible{opacity:1}
.cabecera .ayuda{margin-top:12px}

main{padding:30px 28px 84px;display:flex;flex-direction:column;gap:38px}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.09em;color:var(--tenue);
  font-weight:650}

/* ── Panel: qué toca ahora, y los números al lado ─────────────────────── */
.rejilla-panel{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(260px,1fr);
  gap:14px;align-items:stretch}
.rejilla-panel>*,.kpi,.ahora{min-width:0}
.sello,.ahora .titulo,.ahora .lanzar,.ahora .donde,.item-cab h3,.kpi small{
  overflow-wrap:anywhere}
.ahora{background:var(--papel);border:1px solid var(--linea);border-radius:var(--r);
  padding:20px 22px;box-shadow:var(--sombra);position:relative;overflow:hidden}
.ahora::before{content:"";position:absolute;inset:0 auto 0 0;width:3px;background:var(--acento)}
.ahora.en-curso::before{background:var(--curso)}
.ahora.completo::before{background:var(--hecho)}
.ahora .micro{color:var(--acento-tinta)}
.ahora.en-curso .micro{color:var(--curso)}
.ahora.completo .micro{color:var(--hecho)}
.ahora .titulo{display:block;margin-top:9px;font-size:19px;font-weight:620;
  line-height:1.35;letter-spacing:-.015em;text-decoration:none;text-wrap:balance}
.ahora .titulo:hover{text-decoration:underline;text-underline-offset:3px}
.ahora .titulo .id{display:block;font-family:var(--f-datos);font-size:12.5px;
  font-weight:500;color:var(--tenue);margin-bottom:5px;letter-spacing:0}
.ahora .donde{margin-top:8px;color:var(--tenue);font-size:13px}
.ahora .meta{margin-top:12px}
.ahora .lanzar{margin-top:14px;padding-top:12px;border-top:1px solid var(--linea-2);
  color:var(--tenue);font-size:12.5px}

.kpis{display:flex;flex-direction:column;gap:10px}
.abiertos{grid-column:1/-1;background:var(--papel);border:1px solid var(--linea);
  border-left:3px solid var(--curso);border-radius:var(--r);padding:15px 18px;
  box-shadow:var(--sombra);display:flex;flex-direction:column;gap:6px}
.abiertos .micro{color:var(--curso)}
.abiertos a{font-size:14px;text-decoration:none}
.abiertos a:hover{text-decoration:underline}
.abiertos a code{color:var(--tenue);margin-right:7px;font-size:12px}
.pista-abiertos{color:var(--tenue);font-size:12.5px;margin-top:2px}
.kpi{background:var(--papel);border:1px solid var(--linea);border-radius:var(--r);
  padding:14px 18px;box-shadow:var(--sombra);flex:1;display:flex;flex-direction:column;
  justify-content:center}
.kpi b{font-size:27px;font-weight:660;letter-spacing:-.03em;line-height:1.05}
.kpi .unidad{font-size:16px;font-weight:560;color:var(--tenue);margin-left:2px}
.kpi .et{font-size:12.5px;color:var(--tinta-2);margin-top:1px}
.kpi small{color:var(--tenue);font-size:12px;margin-top:5px}
.kpi .barra{margin-top:9px}

.avisos{margin-top:14px;background:var(--papel);border:1px solid var(--linea);
  border-radius:var(--r);padding:13px 18px}
.avisos summary{cursor:pointer;font-size:13.5px;display:flex;align-items:center;gap:9px}
.avisos pre{white-space:pre-wrap;font-size:12.5px;color:var(--tinta-2);margin-top:11px;
  font-family:var(--f-datos)}

/* ── Barras de estado ─────────────────────────────────────────────────────
   2 px de hueco entre segmentos: pegados, dos estados contiguos se leen como
   uno solo. El hueco se pinta con el fondo de la tarjeta, no con transparencia,
   para que no cambie según lo que haya detrás. */
.barra{display:flex;gap:2px;height:6px;border-radius:99px;overflow:hidden;
  background:var(--pista)}
.barra.fina{height:5px}
.seg{display:block;min-width:3px;border-radius:99px}
.seg.e-hecho{background:var(--hecho)} .seg.e-en_curso{background:var(--curso)}
.seg.e-pendiente{background:var(--pista)} .seg.e-bloqueado{background:var(--bloq)}
.seg.e-descartado{background:var(--desc)} .seg.e-sin_estado{background:var(--tenue)}
.punto{width:7px;height:7px;border-radius:99px;display:inline-block;flex:none}
.punto.e-hecho{background:var(--hecho)} .punto.e-en_curso{background:var(--curso)}
.punto.e-pendiente{background:var(--pista);box-shadow:inset 0 0 0 1px var(--tenue)}
.punto.e-bloqueado{background:var(--bloq)} .punto.e-descartado{background:var(--desc)}
.punto.e-sin_estado{background:var(--tenue)}

/* ── Mapa de olas ─────────────────────────────────────────────────────── */
.mapa .filas{display:flex;flex-direction:column;gap:1px;background:var(--papel);
  border:1px solid var(--linea);border-radius:var(--r);padding:6px;box-shadow:var(--sombra)}
.fila{display:grid;grid-template-columns:58px minmax(0,1fr) 150px 52px 62px;
  align-items:center;gap:16px;padding:10px 12px;border-radius:7px;text-decoration:none;
  transition:background .12s}
.fila:hover{background:var(--hundido)}
.fila .n{color:var(--tenue);font-size:11.5px;text-transform:uppercase;letter-spacing:.07em}
.fila .nom{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:14px}
.fila .frac,.fila .hs{text-align:right;color:var(--tenue);font-size:12.5px;
  font-family:var(--f-datos)}
.fila .nada{opacity:.45}

/* ── Barra de control ─────────────────────────────────────────────────── */
.barra-control{position:sticky;top:0;z-index:5;display:flex;gap:12px;align-items:center;
  flex-wrap:wrap;padding:12px 0;margin:-8px 0 -14px;
  background:linear-gradient(var(--fondo) 72%,transparent);backdrop-filter:blur(8px)}
#q{flex:1 1 220px;min-width:180px;padding:9px 13px;border:1px solid var(--linea);
  border-radius:8px;background:var(--papel);color:var(--tinta);font:inherit;font-size:13.5px}
.busca{display:contents}
.segmentos{display:flex;gap:4px;flex-wrap:wrap}
.f{display:inline-flex;align-items:center;gap:6px;border:1px solid var(--linea);
  background:var(--papel);color:var(--tinta-2);border-radius:99px;padding:6px 13px;
  font:inherit;font-size:12.5px;cursor:pointer;transition:border-color .12s,color .12s}
.f b{font-weight:600;color:var(--tenue)}
.f:hover{border-color:var(--tenue);color:var(--tinta)}
.f.activo{background:var(--tinta);color:var(--papel);border-color:var(--tinta)}
.f.activo b{color:var(--papel);opacity:.72}
.cuenta{font-size:12.5px;color:var(--tenue);margin-left:auto}

/* ── Olas e ítems ─────────────────────────────────────────────────────── */
.ola{display:flex;flex-direction:column;gap:12px}
.ola-cab h2{display:flex;align-items:baseline;gap:11px;font-size:18px;text-transform:none;
  letter-spacing:-.015em;color:var(--tinta);margin-bottom:10px}
.ola-cab h2 .n{font-size:11.5px;text-transform:uppercase;letter-spacing:.09em;
  color:var(--tenue);flex:none}
.ola-cab h2 .frac{margin-left:auto;font-size:12.5px;font-weight:500;color:var(--tenue);
  font-family:var(--f-datos);flex:none}
.ola-cab .barra{height:4px}
.criterios{margin:0;padding:15px 20px;background:var(--hundido);border:1px solid var(--linea);
  border-radius:var(--r);display:flex;flex-direction:column;gap:12px}
.items{display:flex;flex-direction:column;gap:9px}

.item{background:var(--papel);border:1px solid var(--linea);border-radius:var(--r);
  padding:17px 20px;box-shadow:var(--sombra);scroll-margin-top:78px;position:relative}
.item::before{content:"";position:absolute;inset:0 auto 0 0;width:3px;
  border-radius:var(--r) 0 0 var(--r)}
.item.e-en_curso::before{background:var(--curso)}
.item.e-bloqueado::before{background:var(--bloq)}
.item.e-hecho{background:var(--hundido)}
.item.e-descartado{opacity:.55}
.item.oculto{display:none}
.item:target{outline:2px solid var(--acento);outline-offset:2px}
.item-cab{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.item-cab h3{flex:1 1 100%;font-size:16px;line-height:1.42;font-weight:600;margin-top:2px}
.estado{display:inline-flex;align-items:center;gap:6px;font-size:11.5px;font-weight:620;
  letter-spacing:.02em;color:var(--tinta-2)}
.item-cab .id{font-family:var(--f-datos);font-size:12px;color:var(--tenue);
  text-decoration:none}
.item-cab .id:hover{color:var(--acento-tinta);text-decoration:underline}
.chip{display:inline-flex;align-items:center;padding:3px 10px;border-radius:99px;
  font-size:11.5px;border:1px solid var(--linea);color:var(--tenue);white-space:nowrap}
.chip.dato{font-family:var(--f-datos);font-size:11px}
.chip.coste{border-color:color-mix(in srgb,var(--acento) 45%,var(--linea));
  color:var(--acento-tinta)}
.chip.ojo{border-color:color-mix(in srgb,var(--bloq) 40%,var(--linea));color:var(--bloq)}
.meta{display:flex;gap:6px;flex-wrap:wrap;margin-top:12px}

.detalle{margin:15px 0 0;display:flex;flex-direction:column;gap:12px}
.campo{display:grid;grid-template-columns:170px minmax(0,1fr);gap:18px;align-items:start}
.campo dt{color:var(--tenue);font-size:12.5px;line-height:1.5}
.campo dd{margin:0;font-size:14px;min-width:0;max-width:72ch;overflow-wrap:anywhere;
  color:var(--tinta-2)}
.campo.c-resultado dd,.campo.c-rollback dd{border-left:2px solid var(--linea);
  padding-left:13px}
.campo.c-verificacion_comando dd,.campo.c-archivos dd,.campo.c-commit dd{
  font-family:var(--f-datos);font-size:12.5px}
.campo.otras dd{display:flex;flex-direction:column;gap:9px}
.nota b{color:var(--tenue);font-weight:620;margin-right:6px}
.lista{margin:0;padding-left:18px} .lista li{margin:2px 0}
.anidado{margin:0} .anidado dt{color:var(--tenue);font-size:12.5px;margin-top:7px}
.anidado dd{margin:0}
.bool{color:var(--tenue)}
.ref{color:var(--acento-tinta);text-decoration:none;border-bottom:1px dotted}
/* Un `resultado` de veinte líneas es lo más valioso del ledger y lo peor de
   escanear: se pliega, no se esconde. El recorte lo pone el JS, así que sin JS
   —o al imprimir— todo sale entero. */
.detalle dd.recortado{max-height:138px;overflow:hidden;
  -webkit-mask-image:linear-gradient(#000 66%,transparent);
  mask-image:linear-gradient(#000 66%,transparent)}
.mas{grid-column:2;justify-self:start;margin-top:2px;font:inherit;font-size:12px;
  color:var(--acento-tinta);background:none;border:0;padding:0;cursor:pointer}
.mas:hover{text-decoration:underline}

/* ── Cronología ───────────────────────────────────────────────────────── */
.crono .grafico{display:flex;align-items:flex-end;gap:2px;height:124px;
  padding:22px 16px 0;background:var(--papel);border:1px solid var(--linea);
  border-radius:var(--r);overflow-x:auto;box-shadow:var(--sombra)}
.crono .col{position:relative;flex:0 0 46px;display:flex;flex-direction:column;
  justify-content:flex-end;align-items:center;height:100%;gap:6px;padding-bottom:9px;
  box-shadow:inset 0 -1px 0 var(--linea)}
.crono .tallo{width:100%;max-width:16px;background:var(--hecho);border-radius:3px 3px 0 0;
  min-height:3px;position:relative}
.crono .valor{position:absolute;bottom:100%;left:50%;transform:translateX(-50%);
  margin-bottom:4px;font-size:11px;color:var(--tinta-2);font-weight:620}
.crono .dia{font-size:10px;color:var(--tenue);white-space:nowrap;font-family:var(--f-datos)}
.crono .tip{position:absolute;bottom:calc(100% - 6px);left:50%;transform:translateX(-50%);
  display:none;background:var(--tinta);color:var(--fondo);font-size:11.5px;line-height:1.45;
  padding:7px 10px;border-radius:7px;max-width:280px;z-index:9;text-align:left}
.crono .col:hover .tip,.crono .col:focus-within .tip{display:block}
.crono .tabla{margin-top:12px}
.crono .tabla summary{cursor:pointer;font-size:12.5px;color:var(--tenue)}
.crono table{border-collapse:collapse;margin-top:10px;font-size:12.5px;width:100%}
.crono th,.crono td{text-align:left;padding:6px 12px 6px 0;border-bottom:1px solid var(--linea-2);
  vertical-align:top}
.crono th{color:var(--tenue);font-weight:620}
.crono .num{text-align:right;padding-right:18px}

.notas dl{margin:0;display:flex;flex-direction:column;gap:13px;background:var(--papel);
  border:1px solid var(--linea);border-radius:var(--r);padding:17px 20px}
.notas .campo dd{color:var(--tenue);font-size:13.5px}
.pie-pag{border-top:1px solid var(--linea);padding:22px 0 44px;color:var(--tenue);
  font-size:12.5px}
.vacio{padding:34px;text-align:center;color:var(--tenue);font-size:14px;
  border:1px dashed var(--linea);border-radius:var(--r)}

@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}

@media print{
  /* Un PDF con los filtros aplicados y media página en blanco no es un informe:
     se imprime el estado completo, sin controles. */
  .acciones,.barra-control,.pie-pag,.saltar,.cabecera .ayuda{display:none!important}
  .item.oculto{display:block!important}
  .ola{display:block!important}
  body{background:#fff;color:#000}
  .item,.kpi,.criterios,.notas dl,.mapa .filas{break-inside:avoid;box-shadow:none}
  .detalle dd.recortado{max-height:none!important;-webkit-mask-image:none!important;
    mask-image:none!important}
  .mas{display:none}
  .crono .tabla{display:none}
}

@media (max-width:860px){
  .rejilla-panel{grid-template-columns:1fr}
  .kpis{flex-direction:row;flex-wrap:wrap}
  .kpi{flex:1 1 180px}
}
@media (max-width:720px){
  .ancho{padding:0 18px} main{padding:22px 18px 60px}
  .kpis{flex-direction:column}
  .cabecera{padding:26px 0 22px} .cabecera h1{font-size:24px}
  .campo{grid-template-columns:1fr;gap:4px}
  .mas{grid-column:1}
  .fila{grid-template-columns:52px minmax(0,1fr) 48px;gap:12px}
  .fila .barra,.fila .hs{display:none}
  .cuenta{margin-left:0}
}
"""

JS = r"""
(function(){
  var q=document.getElementById('q'), cuenta=document.getElementById('cuenta');
  var items=[].slice.call(document.querySelectorAll('.item'));
  var estado='todo', texto='';

  function aplicar(){
    var vistos=0;
    items.forEach(function(it){
      var ok=(estado==='todo'||it.dataset.estado===estado)&&
             (!texto||it.dataset.busca.indexOf(texto)>=0);
      it.classList.toggle('oculto',!ok); if(ok)vistos++;
    });
    // Una ola sin ningún ítem visible sobra: deja un hueco con criterios que no
    // vienen a cuento de lo que se está buscando.
    [].forEach.call(document.querySelectorAll('.ola'),function(o){
      o.style.display=o.querySelector('.item:not(.oculto)')?'':'none';
    });
    cuenta.textContent=(estado==='todo'&&!texto)
      ? items.length+' ítems'
      : 'mostrando '+vistos+' de '+items.length;
    var v=document.getElementById('vacio');
    if(!v){v=document.createElement('p');v.id='vacio';v.className='vacio';
      v.textContent='Ningún ítem encaja con ese filtro.';
      document.querySelector('main').appendChild(v);}
    v.style.display=vistos?'none':'';
  }

  q.addEventListener('input',function(){texto=q.value.trim().toLowerCase();aplicar();});
  [].forEach.call(document.querySelectorAll('.f'),function(b){
    b.addEventListener('click',function(){
      [].forEach.call(document.querySelectorAll('.f'),function(x){
        x.classList.remove('activo'); x.setAttribute('aria-pressed','false');
      });
      b.classList.add('activo'); b.setAttribute('aria-pressed','true');
      estado=b.dataset.f; aplicar();
    });
  });
  aplicar();

  // ── Plegado de los campos largos ─────────────────────────────────────────
  // Se hace aquí y no en el HTML a propósito: si el JS no corre, la página
  // sigue mostrando el texto entero. Un visor que oculta registro por defecto
  // es peor que uno feo.
  [].forEach.call(document.querySelectorAll('.detalle dd'),function(dd){
    if(dd.scrollHeight<=176)return;
    dd.classList.add('recortado');
    var b=document.createElement('button');
    b.className='mas'; b.type='button'; b.textContent='mostrar todo';
    b.addEventListener('click',function(){
      b.textContent=dd.classList.toggle('recortado')?'mostrar todo':'plegar';
    });
    dd.parentNode.appendChild(b);
  });

  // ── Compartir ─────────────────────────────────────────────────────────────
  // El botón existe para que nadie tenga que saber dónde quedó el archivo. Lo
  // que descarga es ESTA página serializada, no una lectura del disco: así
  // funciona igual servida en vivo que abierta desde file://.
  var aviso=document.getElementById('aviso'), t=null;
  function decir(m){aviso.textContent=m;aviso.classList.add('visible');
    clearTimeout(t);t=setTimeout(function(){aviso.classList.remove('visible')},2600);}

  function copiaLimpia(){
    var doc=document.documentElement.cloneNode(true);
    // Fuera lo del modo vivo: la copia tiene que abrirse sin servidor detrás.
    ['#vivo','#vivo-js','#aviso'].forEach(function(sel){
      var n=doc.querySelector(sel); if(n&&n.parentNode)n.parentNode.removeChild(n);
    });
    // Y fuera el filtro que hubiera puesto: se comparte el plan entero, no la
    // búsqueda de quien lo compartió.
    [].forEach.call(doc.querySelectorAll('.item.oculto'),function(n){n.classList.remove('oculto')});
    [].forEach.call(doc.querySelectorAll('.ola'),function(n){n.style.display=''});
    var v=doc.querySelector('#vacio'); if(v&&v.parentNode)v.parentNode.removeChild(v);
    // El plegado lo vuelve a calcular la copia al abrirse: si se fuera con los
    // botones puestos, saldrían duplicados.
    [].forEach.call(doc.querySelectorAll('.mas'),function(n){n.parentNode.removeChild(n)});
    [].forEach.call(doc.querySelectorAll('.recortado'),function(n){n.classList.remove('recortado')});
    var e=doc.querySelector('#q'); if(e)e.removeAttribute('value');
    return '<!doctype html>\n'+doc.outerHTML;
  }

  document.getElementById('btn-guardar').addEventListener('click',function(){
    var a=document.createElement('a');
    a.href=URL.createObjectURL(new Blob([copiaLimpia()],{type:'text/html'}));
    a.download=__ARCHIVO__;
    document.body.appendChild(a);a.click();document.body.removeChild(a);
    setTimeout(function(){URL.revokeObjectURL(a.href)},4000);
    decir('descargado — ya se puede adjuntar');
  });

  document.getElementById('btn-resumen').addEventListener('click',function(){
    var texto=__RESUMEN__;
    function respaldo(){
      // navigator.clipboard no existe en file:// en algunos navegadores. Sin
      // esto el botón no haría nada justo en el caso más común: el archivo
      // abierto de un doble clic.
      var ta=document.createElement('textarea');ta.value=texto;
      ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);
      ta.select();
      var ok=false; try{ok=document.execCommand('copy')}catch(_){}
      document.body.removeChild(ta);
      decir(ok?'resumen copiado':'no he podido copiar — usa Guardar copia');
    }
    if(navigator.clipboard&&navigator.clipboard.writeText){
      navigator.clipboard.writeText(texto).then(function(){decir('resumen copiado')},respaldo);
    } else respaldo();
  });

  document.getElementById('btn-pdf').addEventListener('click',function(){window.print()});

  // Lo único que sale del cierre. No es API para nadie: es para que la suite
  // pueda comprobar QUÉ se comparte sin simular una descarga, que en un
  // navegador sin sesión gráfica se queda colgada.
  window.__arnesVer={copiaLimpia:copiaLimpia,resumen:__RESUMEN__};
})();
"""

# Sólo se inyecta al SERVIR con --live. El archivo del disco no lo lleva: tiene
# que poder abrirse desde file:// sin que un fetch fallido escriba errores en la
# consola de quien lo recibió por chat.
POLLER = r"""
<script id="vivo-js">
(function(){
  var ultimo=null;
  setInterval(function(){
    fetch('__cambio',{cache:'no-store'}).then(function(r){return r.text()}).then(function(t){
      if(ultimo===null){ultimo=t;return}
      if(t!==ultimo){location.reload()}
    }).catch(function(){});
  },1500);
})();
</script>
<div id="vivo">en vivo · se recarga al cambiar el ledger</div>
<style>
#vivo{position:fixed;right:16px;bottom:16px;z-index:99;background:var(--papel);
  border:1px solid var(--linea);border-radius:99px;padding:7px 14px;font-size:11.5px;
  color:var(--tenue);box-shadow:var(--sombra)}
@media print{#vivo{display:none}}
</style>
"""
# ── Escritura y servidor ────────────────────────────────────────────────────
def escribir(destino, html_txt):
    carpeta = os.path.dirname(os.path.abspath(destino))
    if carpeta:
        os.makedirs(carpeta, exist_ok=True)
    with open(destino, 'w', encoding='utf-8') as fh:
        fh.write(html_txt)
    return destino


def destino_temporal(proyecto):
    """Dónde vive la página cuando nadie ha pedido un sitio.

    En el temporal del sistema, no dentro del repositorio: un artefacto
    generado que aparece en `git status` obliga a decidir si se versiona, y esa
    es una pregunta que el visor no tiene por qué plantearle a nadie. Compartir
    se hace con el botón de la página, así que la ruta no necesita ser bonita
    ni recordable — sólo estable, para que `--live` sepa si está al día y para
    no dejar un archivo nuevo por cada ejecución.
    """
    firma = hashlib.sha1(os.path.abspath(proyecto).encode('utf-8')).hexdigest()[:10]
    nombre = os.path.basename(proyecto.rstrip('/')) or 'proyecto'
    return os.path.join(tempfile.gettempdir(), 'arnes-plan',
                        '%s-%s' % (slug(nombre), firma), 'plan.html')


def desactualizada(destino, ledger):
    """La guarda que pide el contrato de --live: la página del disco vale sólo
    si existe y es más nueva que el ledger. Si no, se regenera antes de servir,
    y así el archivo que alguien mande por chat es siempre el último fiel."""
    if not os.path.isfile(destino):
        return True
    try:
        return os.path.getmtime(destino) < os.path.getmtime(ledger)
    except OSError:
        return True


def servir(destino, ledger, version, proyecto, puerto, abrir):
    import http.server
    import socketserver

    estado = {'html': None, 'mtime': None}

    def refrescar(forzar=False):
        try:
            m = os.path.getmtime(ledger)
        except OSError:
            m = None
        if forzar or m != estado['mtime'] or estado['html'] is None:
            estado['html'] = generar(ledger, version, proyecto)
            estado['mtime'] = m
            escribir(destino, estado['html'])   # el archivo del disco, siempre al día
        return estado['html']

    class Mano(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            ruta = self.path.split('?')[0].lstrip('/')
            if ruta == '__cambio':
                try:
                    cuerpo = str(os.path.getmtime(ledger))
                except OSError:
                    cuerpo = 'sin-ledger'
                self._responder(cuerpo, 'text/plain; charset=utf-8')
                return
            try:
                pagina = refrescar()
            except Exception as exc:   # un ledger a medio escribir no tumba el servidor
                self._responder('<h1>El ledger no se puede leer ahora mismo</h1><pre>%s</pre>'
                                '<p>Se reintenta al recargar.</p>' % e(exc), 'text/html; charset=utf-8')
                return
            self._responder(pagina.replace('<!--VIVO-->', POLLER), 'text/html; charset=utf-8')

        def _responder(self, cuerpo, tipo):
            datos = cuerpo.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', tipo)
            self.send_header('Content-Length', str(len(datos)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(datos)

        def log_message(self, *a):
            pass   # el servidor de una vista no tiene por qué narrar cada GET

    refrescar(forzar=True)
    socketserver.TCPServer.allow_reuse_address = True
    try:
        srv = socketserver.TCPServer(('127.0.0.1', puerto), Mano)
    except OSError as exc:
        print('arnes ver: no puedo escuchar en el puerto %d (%s).' % (puerto, exc), file=sys.stderr)
        print('           Prueba con otro:  arnes ver --live --puerto %d' % (puerto + 1), file=sys.stderr)
        return 1
    url = 'http://127.0.0.1:%d/' % srv.server_address[1]
    print('  en vivo   %s' % url, flush=True)
    print('  Se regenera sola al cambiar el ledger. Ctrl-C para parar.', flush=True)
    print('  Para compartirla, "Guardar copia" en la propia página.', flush=True)
    if abrir:
        _abrir(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print('\n  parado.')
    finally:
        srv.server_close()
    return 0


def _abrir(destino):
    """Abrir de verdad, no 'intentarlo'. webbrowser falla callado en algunos
    entornos (WSL, servidores sin sesión gráfica) y la ruta ya se imprimió
    antes, así que un fallo aquí no deja a nadie sin nada."""
    try:
        import webbrowser
        webbrowser.open(destino if destino.startswith('http') else 'file://' + os.path.abspath(destino))
    except Exception:
        pass


def version_del_plugin():
    try:
        with open(os.path.join(AQUI, '..', '.claude-plugin', 'plugin.json'), encoding='utf-8') as fh:
            return json.load(fh)['version']
    except Exception:
        return '?'


def main(argv=None):
    p = argparse.ArgumentParser(
        prog='arnes ver', add_help=True,
        description='Genera la vista web del plan desde el ledger. Sin inferencia.')
    p.add_argument('--live', action='store_true',
                   help='sirve la página y la regenera al cambiar el ledger')
    p.add_argument('--puerto', type=int, default=7373, help='puerto de --live (def. 7373)')
    p.add_argument('--salida', metavar='RUTA', default=None,
                   help='escribir el .html en una ruta concreta (def. un temporal)')
    p.add_argument('--no-abrir', action='store_true', help='no abrir el navegador')
    args = p.parse_args(argv)

    proyecto = raiz()
    ledger = resolver(proyecto)
    if not ledger:
        print('arnes ver: no encuentro el ledger bajo %s.' % proyecto, file=sys.stderr)
        print('           Créalo con:  arnes arrancar', file=sys.stderr)
        return 1

    destino = args.salida or destino_temporal(proyecto)
    version = version_del_plugin()

    if args.live:
        # El contrato que pidió existir: --live no exige haber corrido `ver`
        # antes. Si la página no está o el ledger es más nuevo, la genera él.
        if desactualizada(destino, ledger):
            # El contrato: --live no obliga a haber corrido `arnes ver` antes.
            print('  (no había página al día: se genera ahora)')
        return servir(destino, ledger, version, proyecto, args.puerto, not args.no_abrir)

    try:
        pagina = generar(ledger, version, proyecto)
    except Exception as exc:
        print('arnes ver: no puedo generar la página: %s' % exc, file=sys.stderr)
        return 1
    escribir(destino, pagina)
    if args.salida or args.no_abrir:
        # Sólo se anuncia la ruta cuando alguien la pidió o cuando no se va a
        # abrir nada: en el camino normal el archivo no es asunto de nadie.
        print('  archivo   %s' % destino)
    if not args.no_abrir:
        print('  Abierta en el navegador. Para mandarla, el botón "Guardar copia"')
        print('  de la propia página; para pegarla en un chat, "Copiar resumen".')
        _abrir(destino)
    return 0


if __name__ == '__main__':
    sys.exit(main())
