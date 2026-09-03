#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
docs.py — Abre la documentación del arnés.

Uso:
  arnes docs             la página de la versión instalada, en el navegador
  arnes docs --web       la publicada en GitHub Pages
  arnes docs --no-abrir  sólo imprime las direcciones

Por qué existe, y por qué abre la copia LOCAL por defecto: el arnés ya tiene una
regla —no ofrecer nunca una ruta que apunte a una versión distinta de la que se
está ejecutando— y la publicada es exactamente eso. La página de Pages es la de
`main`; la instalada puede ser anterior o posterior. Leer una condición que en
tu copia no se comporta así es peor que no leer nada, porque no se nota. La
dirección publicada se imprime igual, para compartirla con quien no tiene el
plugin instalado.
"""
import argparse
import json
import os
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

AQUI = os.path.dirname(os.path.abspath(__file__))
PAGINA = os.path.normpath(os.path.join(AQUI, '..', 'docs', 'index.html'))
PUBLICADA = 'https://danielwueno.github.io/arnes-plan/'


def version():
    try:
        with open(os.path.join(AQUI, '..', '.claude-plugin', 'plugin.json'),
                  encoding='utf-8') as fh:
            return json.load(fh)['version']
    except Exception:
        return '?'


def abrir(destino):
    try:
        import webbrowser
        webbrowser.open(destino if destino.startswith('http')
                        else 'file://' + os.path.abspath(destino))
        return True
    except Exception:
        return False


def main(argv=None):
    p = argparse.ArgumentParser(
        prog='arnes docs', add_help=True,
        description='Abre la documentación del arnés: modos, guardas y comandos.')
    p.add_argument('--web', action='store_true',
                   help='abrir la publicada en vez de la de esta versión')
    p.add_argument('--no-abrir', action='store_true', help='sólo imprimir las direcciones')
    args = p.parse_args(argv)

    v = version()
    local_hay = os.path.isfile(PAGINA)

    if args.web or not local_hay:
        if not local_hay and not args.web:
            print('  (esta instalación no trae la página; se abre la publicada)')
        destino, etiqueta = PUBLICADA, 'publicada'
    else:
        destino, etiqueta = PAGINA, 'v%s, la de esta instalación' % v

    print('  documentación   %s' % destino)
    print('  %s' % etiqueta)
    if not args.web and local_hay:
        print('  para compartir  %s' % PUBLICADA)
        print('                  (es la de `main`, que puede no ser la v%s)' % v)
    if not args.no_abrir:
        abrir(destino)
    return 0


if __name__ == '__main__':
    sys.exit(main())
