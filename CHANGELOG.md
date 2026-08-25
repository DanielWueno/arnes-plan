# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado: [SemVer](https://semver.org/lang/es/).

El **mayor** cambia cuando cambia el formato del ledger, porque eso obliga a
tocar los ledgers en uso. Un menor añade campos que un lector viejo ignora.

## [1.3.0] — 2026-08-25

### Corregido
- **El arranque documentado podía destruir el plan de otro.** Decía
  `cp plantilla docs/plan/ejecucion-plan.estado.json`: el segundo miembro del
  equipo clonaba el repositorio, seguía el README al pie de la letra, y le
  pasaba por encima al ledger del primero. Sin preguntar, y sobre el único
  fichero que registra el avance. Ahora el arranque es `arrancar.sh`, que
  detecta si ya hay plan y **nunca sobrescribe**: si lo hay, valida el que hay
  y anuncia el ítem que toca; si no, siembra. Correrlo dos veces no hace daño.
  Un README que avisara "si ya existe, no lo copies" habría sido la misma clase
  de regla que este proyecto lleva moviendo al código desde el principio.
- **El README mandaba a `claude plugin list` a buscar la ruta de instalación,
  y ese comando no la da.** Sólo nombre, versión, scope y estado; hace falta
  `claude plugin list --json`, que sí trae `installPath`. Queda documentada la
  línea que resuelve `$ARNES` preguntándole al CLI, en vez de clavar un número
  de versión que caduca en cada `plugin update` — que es exactamente cómo se
  quedó obsoleta la ruta que la gente tenía copiada.
- Documentado que `claude plugin update` exige el nombre cualificado
  (`arnes-plan@arnes-plan`); a secas falla con "Plugin not found".

### Añadido
- `scripts/arrancar.sh`, y con él una puesta en marcha de un solo comando que
  se explica sola: imprime al terminar la línea de `export ARNES` ya resuelta,
  para no tener que volver al README a buscarla.

## [1.2.0] — 2026-08-25

### Añadido
- **Los dos diagramas del arnés en el README**, que GitHub renderiza solo: una
  invocación de principio a fin —con las puertas de cierre dibujadas fuera de
  la sesión que hizo el trabajo— y el ciclo de vida de un ítem con la condición
  escrita en cada arista. Es la explicación que antes costaba tres párrafos.
- `docs/como-funciona.html`, la misma explicación como página, para proyectar
  en una reunión o imprimir a PDF.
- `scripts/validar-diagramas.py`, y con él la razón de que las dos cosas
  anteriores puedan convivir: el mismo Mermaid tiene que vivir en dos sitios
  porque cada uno sirve a un público distinto, y dos copias del mismo texto se
  desincronizan solas. El script falla si dejan de coincidir, así que un
  diagrama viejo no llega a proyectarse. Compara el diagrama, no el documento:
  la página tiene prosa propia y reescribirla no pone el CI en rojo.

## [1.1.0] — 2026-08-25

Un ítem volvía marcado `hecho` porque lo marcaba el mismo agente que lo había
hecho, y el arnés se lo creía. Esta versión añade las dos comprobaciones de
cierre que no dependen de su palabra.

El esquema del ledger sigue en la versión 1: `verificacion_comando` es un campo
que un lector viejo ignora. Con la contrapartida de que lo ignora *en silencio*
— un arnés 1.0.x sobre un ledger que lo usa no correrá la verificación y no
dirá nada. Si repartes el ledger, reparte la versión del plugin con él.

### Añadido
- **`verificacion_comando`**, campo opcional del ítem. Es la parte de
  `verificacion` que una máquina puede decidir sola, y `plan-run.sh` la corre
  **él**, en la raíz del proyecto, después de que la sesión haya terminado.
  Corrido fuera de la sesión que declaró el ítem hecho, es la diferencia entre
  "el agente dice que pasa" y "pasa". Lleva perro guardián propio
  (`ARNES_LIMITE_VERIFICACION`, 900 s por defecto): sin él, un comando colgado
  dejaría una sesión `--desatendido` esperando para siempre.
- **`resultado` obligatorio al cerrar.** Un ítem que pasa a `hecho` sin decir
  qué se hizo y qué evidencia lo prueba no cuenta como cerrado. Se reclama en
  el momento del cierre (`validar-ledger.py --al-cerrar`) y no en el barrido
  general, por la misma razón que `rollback` sólo se le pide a lo que aún se va
  a ejecutar: reclamárselo a lo ya cerrado sería ruido permanente.
- **Techo de reintentos y parada por hueco de ficha**, en el protocolo del
  comando. Tres intentos sobre una verificación en rojo son depuración; el
  cuarto es prueba y error. Y una ambigüedad que viene de la ficha —no de la
  implementación— para al instante y se pregunta, sin intentos previos: ningún
  número de intentos rellena un hueco del plan. Eran las dos únicas reglas que
  el arnés no tenía de un flujo de trabajo anterior al ledger; el resto de
  aquel flujo (estado, changelog, elección de modelo, no borrar sin traza,
  criterio de cierre) ya vivía aquí como campo validado en vez de como prosa.
- Ninguna de las dos puertas revierte nada. El commit ya existe y deshacerlo es
  decisión de quien mira, con el `rollback` de la ficha delante; el script se
  limita a salir distinto de 0 y a enseñar por qué.

### Corregido
- **`--desatendido` aceptaba ítems marcados `opus`.** Las guardas miraban las
  horas, el multiagente y el bloqueo, pero no el modelo — justo el campo con el
  que el ledger declara "aquí el CRITERIO es el trabajo". La regla estaba
  escrita en el README y no en el código, que es como una regla deja de
  cumplirse. `--igual` la salta, como las demás.
- La plantilla del ledger apuntaba a `infra/arnes/`, la ruta de cuando el arnés
  vivía vendorizado dentro del proyecto.

## [1.0.0] — 2026-08-24

Primera versión distribuible. Antes vivía vendorizado dentro de un proyecto y
se copiaba con un instalador; el historial de esa etapa se conserva.

### Añadido
- Distribución como plugin de Claude Code: `marketplace add` / `install` /
  `update`, con versión en `plugin.json`.
- `schema_version` en el ledger. El validador se niega a leer un esquema mayor
  que el que conoce en vez de elegir mal en silencio. Un ledger sin el campo se
  trata como versión 1 y no se le reclama nada.
- Suite de regresión en `tests/prueba.sh`, que cubre los tres fallos que la
  extracción podía introducir.

### Corregido
- **La raíz del proyecto se derivaba de dónde vivía el script.** Correcto
  mientras el arnés estaba dentro del repositorio, y silenciosamente erróneo
  instalado como plugin: `git status`, las guardas de árbol sucio y el commit
  de cierre habrían apuntado al repositorio del plugin.
- `--help` cortaba la cabecera a media frase por un rango de líneas fijo.

### Eliminado
- `instalar.sh`. Copiaba los archivos al repositorio destino, que es el modelo
  de distribución que este repo viene a sustituir. Mantener las dos vías
  reintroduce las copias divergentes.
