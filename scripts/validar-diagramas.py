#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Comprueba que los diagramas del README y los de la página de presentación son
el mismo diagrama. Sale 0 si coinciden, 1 si no, y dice cuál se movió.

Por qué existe: el mismo Mermaid tiene que vivir en dos sitios, porque cada uno
sirve a un público distinto —GitHub lo renderiza para quien llega al repositorio,
y la página se proyecta en una reunión— y ninguno de los dos puede leer del otro.
Dos copias del mismo texto es exactamente la clase de cosa que se desincroniza:
alguien corrige el flujo en el README, la página se queda con el dibujo viejo, y
seis meses después se proyecta un diagrama que miente. Este script convierte
"acuérdate de tocar los dos" en algo que falla en el CI.

No valida que el Mermaid sea correcto —para eso hace falta renderizarlo, que es
red y una dependencia de Node—; valida que no haya DOS versiones. Es la parte
que se rompe sola.

Uso:
  python3 validar-diagramas.py [raiz]     # por defecto, la raíz del repo
"""
import html
import os
import re
import sys

README = 'README.md'
PAGINA = os.path.join('docs', 'como-funciona.html')

# Bloque ```mermaid ... ``` en Markdown, y <pre class="mermaid"> ... </pre> en la
# página. La `s` (DOTALL) es lo que deja que el cuerpo tenga saltos de línea.
RE_MD = re.compile(r'^```mermaid[ \t]*\n(.*?)^```[ \t]*$', re.M | re.S)
RE_HTML = re.compile(r'<pre[^>]*\bclass="[^"]*\bmermaid\b[^"]*"[^>]*>(.*?)</pre>',
                     re.S | re.I)


def normalizar(bloque):
    """Compara el diagrama, no su formato. Se ignoran la indentación, los
    espacios al final de línea y las líneas en blanco, porque un editor puede
    tocar cualquiera de las tres sin que el dibujo cambie. Lo que NO se ignora
    es el orden ni el texto de las etiquetas: ahí es donde está el significado.
    En la página el texto va dentro de HTML, así que primero se deshacen las
    entidades: `&gt;` y `>` son la misma flecha."""
    texto = html.unescape(bloque)
    lineas = [l.strip() for l in texto.splitlines()]
    return '\n'.join(l for l in lineas if l)


def extraer(ruta, patron, etiqueta, errores):
    if not os.path.isfile(ruta):
        errores.append(f'No existe {ruta}, que es donde viven los diagramas {etiqueta}.')
        return []
    with open(ruta, encoding='utf-8') as f:
        return [normalizar(m) for m in patron.findall(f.read())]


def main():
    raiz = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '..')
    os.chdir(raiz)

    errores = []
    en_readme = extraer(README, RE_MD, 'del repositorio', errores)
    en_pagina = extraer(PAGINA, RE_HTML, 'de la presentación', errores)
    if errores:
        for e in errores:
            print(f'✗ {e}', file=sys.stderr)
        return 1

    if not en_readme:
        print(f'✗ {README} no tiene ningún bloque ```mermaid.', file=sys.stderr)
        return 1

    if len(en_readme) != len(en_pagina):
        print(f'✗ {README} tiene {len(en_readme)} diagrama(s) y {PAGINA} tiene '
              f'{len(en_pagina)}. Se añadió o se borró uno en un solo sitio.',
              file=sys.stderr)
        return 1

    # El orden importa: el diagrama n del README es el diagrama n de la página.
    # Emparejarlos por contenido escondería justo el caso de haberlos permutado.
    distintos = [i for i, (a, b) in enumerate(zip(en_readme, en_pagina)) if a != b]
    if distintos:
        print(f'✗ {len(distintos)} diagrama(s) divergen entre {README} y {PAGINA}:',
              file=sys.stderr)
        for i in distintos:
            print(f'\n  · diagrama {i + 1} — primera línea que no coincide:', file=sys.stderr)
            a, b = en_readme[i].splitlines(), en_pagina[i].splitlines()
            for n in range(max(len(a), len(b))):
                la = a[n] if n < len(a) else '(no hay más líneas)'
                lb = b[n] if n < len(b) else '(no hay más líneas)'
                if la != lb:
                    print(f'      {README}: {la}', file=sys.stderr)
                    print(f'      {PAGINA}: {lb}', file=sys.stderr)
                    break
        print(f'\n  Se tocó el flujo en un sitio y no en el otro. El README manda: '
              f'copia sus bloques a la página.', file=sys.stderr)
        return 1

    print(f'✓ {len(en_readme)} diagrama(s) idénticos en {README} y {PAGINA}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
