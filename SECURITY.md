# Política de seguridad

## Cómo reportar

En la pestaña **Security** del repositorio, con **Report a vulnerability**. El
aviso llega en privado y no queda publicado mientras se trabaja.

No abras una issue pública para esto: las issues de este repositorio son
visibles para cualquiera, y el arnés se ejecuta en máquinas ajenas.

## Qué versiones reciben arreglos

Sólo la última publicada. No hay ramas de mantenimiento: un arreglo sale como
una versión nueva y se recoge con `claude plugin update arnes-plan`.

## Qué importa en este proyecto

El arnés no es una biblioteca que se importa: es código que se **ejecuta** en la
máquina de quien lo instala, con sus permisos y dentro de su repositorio. Dos
hooks corren solos —uno al abrir sesión y otro después de cada edición de
fichero— y los scripts invocan `git`. Un fallo aquí no filtra datos de un
servidor: ejecuta algo en el portátil de otra persona.

Por eso interesan especialmente:

- Inyección de comandos a través de contenido que el arnés lee y no escribe él
  mismo: el ledger, los identificadores de ítem, las rutas y las variables del
  entorno.
- Cualquier escritura, borrado o commit fuera del proyecto desde el que se
  invoca. El caso realista está documentado en el propio código: derivar la raíz
  del proyecto de dónde vive el script devuelve el repositorio del plugin.
- Que una versión distinta de la instalada acabe ejecutándose sin que se note.

## Qué no es una vulnerabilidad

- **Que el arnés ejecute código y haga commits.** Es su función, está descrita en
  el README y el usuario instala el plugin sabiéndolo.
- **Que `--desatendido` reduzca las confirmaciones.** Es deliberado, tiene cinco
  guardas documentadas y su propósito es justamente ese.
- Avisos de herramientas sobre dependencias que este repositorio no tiene: no
  hay manifiestos ni paquetes de terceros, sólo bash y la biblioteca estándar de
  Python.

## Integridad de lo que se distribuye

Lo que llega a quien instala el plugin es `main`, así que `main` está protegido:
entra sólo por pull request, con la suite en verde, y no admite reescritura ni
borrado. Cada versión publicada tiene una etiqueta `arnes-plan--vX.Y.Z` que no se
puede mover ni borrar, de modo que un número de versión siempre significa el
mismo código.

Para comprobar qué se está ejecutando de verdad:

    arnes --version    # la versión y el commit, en una línea
    arnes doctor       # compara la copia registrada con la que corre

`doctor` sale distinto de cero cuando la copia que se ejecuta no es la instalada,
que es la forma más probable de acabar corriendo código viejo sin enterarse.
