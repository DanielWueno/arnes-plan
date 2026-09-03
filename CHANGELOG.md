# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado: [SemVer](https://semver.org/lang/es/).

El **mayor** cambia cuando cambia el formato del ledger, porque eso obliga a
tocar los ledgers en uso. Un menor añade campos que un lector viejo ignora.

Cada versión tiene una etiqueta `arnes-plan--vX.Y.Z` en el repositorio, y
el número de cada entrada enlaza con lo que cambió respecto a la anterior.
No hay 1.9.x: la serie salta de la 1.8.2 a la 1.10.0.

## [1.16.0] — 2026-09-03

### Añadido
- **El README y la página dicen para qué NO sirve el arnés.** La documentación
  explicaba bien los cuatro problemas que resuelve, pero nada advertía de
  cuándo la herramienta deja de sostener nada: si el ejecutor de un ítem es
  una persona en vez de un agente, cinco de los nueve campos obligatorios
  (`modelo`, `esfuerzo`, `por_que_este_modelo`, `multiagente`,
  `horas_maquina`) pasan a ser relleno y tres de las cinco guardas de
  `--desatendido` dejan de proteger nada; si el criterio no cabe en un
  comando, la puerta de cierre se reduce a comprobar que alguien escribió
  `resultado`, que es la autodeclaración que el arnés existe para no leer
  como evidencia; y si el trabajo no deja diff, el ledger se vuelve una copia
  del plan que se desincroniza el primer día. El modo de fallo que motivó la
  sección no es que el arnés rechace esos casos: es que **los acepta** —el
  validador sale verde— y produce un fichero de estado que nadie actualiza.
  La sección se escribe como tres preguntas con respuesta observable, dice
  qué hacer cuando un plan cae del lado que no es (dejarlo en su gestor de
  tareas y llevar al arnés sólo la rebanada que un agente ejecuta y un
  comando verifica) y nombra también el caso que sí aplica pese a parecer que
  no, para no espantar usos legítimos.
- **`tests/prueba.sh` impide que las dos copias de esa sección diverjan**
  (sección 19): comprueba que existe en `README.md` y que la página trae el
  encabezado —no sólo el enlace del índice—, que las dos nombran los cinco
  campos que la sección declara relleno, y que siguen siendo nueve los campos
  obligatorios de ítem en `validar-ledger.py`, porque el «cinco de los nueve»
  es una cuenta sobre una lista que vive en el código.

## [1.15.0] — 2026-09-03

### Añadido
- **Las olas cerradas del visor se pliegan.** `arnes ver` emitía todas las
  olas y todos sus ítems desplegados: una ola cerrada a N/N ocupaba lo mismo
  que la que está en curso, así que el scroll crecía linealmente con el
  ledger y lo que importa quedaba enterrado entre historia. Ahora una ola con
  todos sus ítems en `hecho` se pliega —con `<details>` nativo, no un
  `display:none` propio, así que Ctrl-F y la impresión siguen llegando a su
  contenido—, mientras que la ola que trae el ítem que anuncia el panel de
  arriba se emite siempre abierta, esté cerrada o no por lo demás. Los
  anclajes que ya se usan (`#it-<id>`, `#ola-N`) abren el pliegue antes de
  saltar, y el filtro/buscador abre las olas que contengan una coincidencia
  y las vuelve a plegar al quitar el filtro. `@media print` fuerza todo
  abierto, igual que ya hacía con `.item.oculto` y `.ola`.
- **Navegación entre olas sin volver arriba a mano.** Ir de la Ola 5 a la Ola
  2 exigía subir hasta el «Mapa de olas», que desaparece del scroll en
  cuanto se avanza. Ahora una barra de navegación pegajosa (dentro de la
  barra de control, ya `sticky`) lista cada ola con su fracción hecho/total
  —calculada una sola vez y compartida con el «Mapa de olas», para que
  nunca puedan divergir—; cada ola cierra con enlaces a la anterior y la
  siguiente, sin emitir el que no existe en los extremos; y un botón
  «arriba» aparece sólo tras hacer scroll, nunca en la primera pantalla.
  Nada de esto sale en `@media print`: en un PDF todas las olas van abiertas
  y en orden, así que no hace falta saltar entre ellas.

## [1.14.0] — 2026-09-02

### Añadido
- **El pie del visor nombra dónde está la documentación, no sólo de qué ledger
  salió.** Quien recibe una copia guardada de la página —HTML exportado,
  abierto meses después en otra máquina— no tenía forma de llegar ni a la
  documentación del proyecto ni a la del arnés salvo que ya se supiera la URL
  de memoria. Ahora, si la raíz del ledger declara `documentacion` con una URL
  `http(s)` válida, el pie la enseña como enlace; y siempre enseña, al lado, la
  documentación del arnés con su versión. Sin el campo, el pie no dice nada en
  su lugar —ausencia de dato es ausencia de línea, no un "no disponible"—, y un
  valor que no sea una URL `http(s)` válida (un esquema `javascript:`, o
  basura) nunca se convierte en enlace ni acaba dentro de un `href`, ni
  siquiera escapado. Las dos líneas quedan legibles al imprimir o exportar a
  PDF, que es justo el caso de uso que las motiva.

### Cambiado
- **La cabecera del visor deja de gastar la primera pantalla en explicarse.**
  `arnes ver` abría con tres botones y un párrafo de ayuda contándolos; se
  quita el botón «Imprimir o PDF» —Cmd/Ctrl-P ya hace lo mismo, y el CSS de
  impresión sigue intacto— y el párrafo `.ayuda` que describía «Guardar copia»
  y «Copiar resumen» pasa a vivir como `title` y `aria-describedby` de cada
  botón: la explicación sigue ahí para quien la necesite —al pasar el ratón, o
  con lector de pantalla— pero ya no ocupa espacio fijo. De paso, «Guardar
  copia» deja de llevar el estilo `.primario`: con un botón menos, marcar uno
  como el principal sobraba.

## [1.13.1] — 2026-09-02

### Corregido
- **`arnes` no arrancaba desde PowerShell ni `cmd`:** `'bash' is not recognized
  as an internal or external command`. El envoltorio `arnes.cmd` invocaba `bash`
  a secas, y el de Git for Windows vive en su propia consola, no en el PATH de
  Windows. Ahora lo localiza él: primero en las rutas de instalación de Git,
  después junto al `git` que haya en el PATH, y sólo al final acepta uno del
  PATH —ese orden importa, porque el `bash` que sí suele estar registrado es el
  de WSL, que no sabe abrir la ruta de Windows que se le pasa—. Si no encuentra
  ninguno, lo dice y sale 127 en vez de fallar con el mensaje de `cmd`. Propaga
  además el código de salida del arnés, que es lo que distingue un cierre limpio
  de uno que no se sostiene.

## [1.13.0] — 2026-09-02

### Añadido
- **El arranque registra `~/.local/bin` en el PATH de Windows.** Allí esa
  carpeta no está en el PATH y ponerla exige editar el registro, que está fuera
  del dominio de quien sólo quería instalar un plugin: la última milla eran tres
  líneas de PowerShell copiadas a mano. Se escribe en el ámbito del **usuario**
  —el de máquina pide administrador y afecta a todas las cuentas—, leyendo antes
  ese mismo ámbito, y no se añade si ya estaba. Si no hay PowerShell, se imprime
  el consejo como hasta ahora en lugar de dar el cambio por hecho. En Unix no
  hace nada: `~/.local/bin` es donde vive el propio `claude`.

### Corregido
- **El consejo de PATH para PowerShell copiaba la PATH del sistema en la del
  usuario.** `$env:Path` de un proceso es la PATH de máquina y la de usuario ya
  fundidas; escribirla entera en el ámbito `User`, como indicaba el arranque,
  deja allí una copia permanente de todas las entradas del sistema: se duplican,
  crecen en cada ejecución y quedan congeladas si el administrador cambia
  alguna. El consejo pasa a leer el ámbito de usuario, añadirle la carpeta y
  escribir sólo eso, más la línea que sirve en la consola ya abierta.

### Notas de implementación
- La suite comprueba que el consejo lea `GetEnvironmentVariable("Path", "User")`
  y que no vuelque `$env:Path` en el ámbito de usuario.

## [1.12.2] — 2026-09-02

### Corregido
- **La página de presentación daba una instalación que no funciona.** El primer
  paso ofrecía `claude plugin install arnes-plan@arnes-plan` sin registrar antes
  el marketplace, de modo que quien la seguía tal cual se encontraba con que el
  plugin no existe. El README traía las dos líneas; la página, sólo la segunda,
  y el pie repetía la incompleta.
- **El arranque descrito en la página era circular.** El paso siguiente pedía
  `arnes arrancar`, pero el lanzador `arnes` lo escribe ese mismo arranque y
  recién instalado el plugin todavía no existe. El primer arranque de cada
  máquina va por `/arnes-plan:plan-arrancar`; `arnes arrancar` sirve del segundo
  proyecto en adelante.
- **Faltaban los requisitos previos y el fichero que se edita.** La página no
  declaraba que hacen falta el CLI de Claude Code y un repositorio git, y mandaba
  sustituir el ítem de ejemplo sin nombrar `docs/plan/ejecucion-plan.estado.json`,
  que sólo aparecía varias secciones más abajo.
- **El README repartía comandos con `$ARNES` sin definir.** La sección
  «Ejecutar», la de «Tu primer ledger» y el primer comando que se le pide a
  quien llega nuevo usaban la forma larga, cuya variable sólo se define dentro
  del bloque plegado que documenta la alternativa a instalar el lanzador. Quien
  siguiera el camino normal recibía `No such file or directory`. Las tres pasan
  a usar `arnes`; la forma larga queda donde la variable existe.
- **`arrancar` imprimía esa misma variable sin resolver** en la línea que
  propone validar el ledger recién sembrado. Pasa a `arnes validar`, que es el
  verbo equivalente y no lleva ruta.
- **La tabla de piezas del README estaba partida por un párrafo.** Las tres
  últimas filas quedaban fuera de la tabla y GitHub las renderizaba como texto.
- **La tabla de campos contradecía al validador.** `esfuerzo` figuraba con tres
  valores de los cinco que se aceptan, y `rollback` como opcional siendo
  obligatorio en todo ítem `pendiente` o `en_curso`.
- **La respuesta sobre ejecución sin supervisión estaba obsoleta.** Indicaba
  editar la llamada a `claude` dentro de `plan-run.sh` —una edición que la
  actualización del plugin descarta— con un modo de permisos que ya no es el que
  usa el script. El modo tiene bandera propia desde la 1.2.0: `--desatendido[=N]`.
- **`horas_maquina` se definía de tres maneras.** La plantilla lo describe como
  tiempo de reloj de la máquina; la página lo negaba («no de reloj») y el README
  omitía de quién es ese reloj. Se unifica: reloj de la máquina, no de persona
  ni tokens.
- **`claude plugin update` aparecía sin cualificar** en la tabla de mensajes del
  README, contra lo que el propio documento exige desde la 1.3.1.

### Cambiado
- Redacción de la sección de instalación en tono descriptivo, alineada con el
  resto de la página. Sin cambios de código ni de comportamiento.

### Notas de implementación
- La suite comprueba que las instrucciones de instalación de la página y del
  README registren el marketplace, y que el primer arranque se pida por el slash
  command. Son datos copiados en dos sitios, que es como divergieron.
- Comprueba también que el README no cite `$ARNES` antes de definirla, que
  liste los cinco valores de `esfuerzo` y que ninguna fila de tabla quede sin
  cabecera; y que la salida de `arrancar` no imprima la variable sin resolver,
  que es la regla que ya cumplía `ayuda.sh`.

## [1.12.1] — 2026-08-31

### Corregido
- **Un bloqueo cuyo bloqueante ya cerró dejaba de frenar.** `bloqueado_por`
  documenta la arista, no su vigencia: nadie limpia el campo cuando el
  bloqueante pasa a `hecho`. Las tres puertas preguntaban por la **presencia**
  del campo, así que un ítem desbloqueado hacía semanas seguía pidiendo
  confirmación en interactivo, era rechazado por `--desatendido` y se anunciaba
  como bloqueado en cada sesión nueva. Ahora se consulta el **estado del
  destino**. El validador ya sabía la respuesta —la informaba al final, como
  "ítem(s) con el bloqueo ya cerrado"—, pero lo hacía en un sitio donde no
  decidía nada, y `plan-run.sh` sólo vuelca esa salida cuando la validación
  falla, que es precisamente cuando no es este caso.

  Una guarda que salta cuando no toca se acaba saltando con `--igual`, la misma
  bandera que desactiva las guardas legítimas. Ése era el daño real.

  Un `bloqueado_por` que apunta a un id **inexistente** cuenta como bloqueo
  vivo: el validador ya lo reporta como error aparte, y ante un id que nadie
  puede resolver, frenar es lo conservador. Una errata en el campo no desactiva
  la guarda en silencio.

### Cambiado
- **La ficha dice por qué un bloqueo no frena** (`esperaba a <id>, que ya está
  hecho: no bloquea`) en vez de callarse. El campo sigue en el ledger y quien lo
  lea lo va a ver; sin la línea, parecería que el arnés se comió un aviso.
- **El visor marca la arista cerrada** junto a "Bloqueado por", en lugar de
  presentarla igual que una vigente. Se marca y no se oculta: la arista es
  cierta y su historia importa.

## [1.12.0] — 2026-08-31

### Añadido
- **`arnes --version`.** Una línea: `arnes 1.12.0 (12fc26a)`. Hasta ahora la
  bandera no existía y caía en el "Bandera desconocida" de `plan-run.sh` con
  salida 1; `-V` y `version` era peor, se interpretaban como id de ítem y
  contestaban "No hay ítem que encaje con: -V". El número sólo se podía leer
  dentro de `--help`, entre cuarenta líneas de banderas. Las tres formas se
  aceptan, y contestan aunque no haya ledger, aunque `claude` no esté en el PATH
  y aunque no haya plugin registrado: es lo primero que se teclea cuando algo va
  mal, y no puede depender de que el entorno esté bien.
  El sha va con el número porque es identidad, no ubicación: dos 1.12.0 con
  distinto commit son código distinto. Sale de git cuando hay repositorio —la
  verdad sobre el código que corre, con sufijo `-sucio` si el árbol lo está— y
  del registro sólo si la copia que se ejecuta es la registrada. Si no se puede
  saber, se calla en vez de inventarlo.
- **`arnes doctor`.** El diagnóstico de la instalación, separado de `--version` a
  propósito: son dos preguntas distintas, y un `--version` de ocho líneas rompe
  tanto la costumbre como `arnes --version | ...`. Pone en una pantalla las
  cuatro identidades que en este arnés pueden discrepar sin avisar — la copia
  registrada, la que de verdad se está ejecutando, la versión del lanzador de
  `~/.local/bin` y el esquema del ledger del proyecto — más los requisitos y si
  hay una versión ya descargada sin instalar. Sale 1 sólo si algo está roto; la
  deriva informativa sale 0, porque un doctor que se pone rojo por lo normal deja
  de leerse.
- **`arnes doctor --limpiar` quita las copias viejas del cache.** El barrido de
  Claude Code descarta plugins que ya no se usan, no versiones antiguas de uno en
  uso: se acumula una por cada `plugin update`, para siempre. En la máquina donde
  se escribió esto había 15. El disco no es el problema —son unos megas—; lo es
  que cada copia sigue siendo un arnés entero y ejecutable, con una ruta
  plausible que alguien pudo pegar en un README o dejar en su historial, y correr
  una vieja es el fallo que `plan-run.sh` sabe avisar pero no puede impedir.
  Conserva la instalada, no toca nada que no lleve el manifiesto del plugin, y no
  borra la copia desde la que se está ejecutando. No hace falta confirmarlo: el
  `doctor` a secas ya lista lo que borraría, así que él es el ensayo en seco.
- **El lanzador se sella con la versión que lo escribió** (`# arnes-lanzador:`).
  `claude plugin update` no reescribe ese fichero —se escribe una vez y sobrevive
  a todas las actualizaciones, que es su virtud y también la única forma de que
  se quede atrás sin que nadie se entere—. Sin marca, la pregunta "¿mi lanzador
  es el de esta versión?" no tenía respuesta comprobable.

### Cambiado
- La consulta al registro de instalación vive en `entorno.sh` (`arnes_registro`)
  y ya no duplicada en `plan-run.sh`, para que `--version`, `doctor` y el aviso
  de "no es la copia instalada" no puedan contestar cosas distintas. El lanzador
  conserva la suya: se ejecuta solo, sin incluir ese fichero.

### Notas de actualización
- Nada que migrar. El esquema del ledger no cambia.
- Los lanzadores escritos antes de esta versión no llevan sello y `doctor` los
  informa como "sin marca". No es un fallo: el lanzador sólo resuelve dónde está
  el plugin y delega, así que quedarse atrás casi nunca se nota. Para alinearlo,
  `arnes arrancar` — no pisa el ledger.

## [1.11.0] — 2026-08-31

### Añadido
- **El validador comprueba las aristas de `bloqueado_por`.** El arnés elige el
  siguiente ítem por orden de documento y no lee ese campo: el ledger no
  planifica, ordena, y la posición en el fichero es el calendario. Eso sólo es
  correcto mientras toda arista apunte hacia atrás. Ahora se rechazan las dos
  formas de romperlo: un `bloqueado_por` que no es el id de ningún ítem —una
  frase en prosa, que ninguna comprobación puede resolver— y uno que apunta a un
  ítem posterior, que llevaría al arnés a proponer el bloqueado con su
  precondición sin cerrar. El error dice dónde mover el ítem.
- **Informe de ítems con el bloqueo ya cerrado.** Al final de una validación que
  pasa, junto al aviso de campos fuera de esquema. Deliberadamente **no** es un
  error: que el bloqueante esté `hecho` es lo que ocurre cada vez que se cierra
  algo, y hacerlo fallar convertiría el caso normal en rojo — un validador que
  grita cuando todo está bien deja de leerse. Pero callarlo tampoco sirve: el
  campo no cambia al cerrarse su bloqueante, así que un ítem se queda ejecutable
  y no se entera nadie. En el consumidor real había dos así, encontrados por
  casualidad en revisiones que iban de otra cosa.

### Notas de actualización
- La comprobación de dirección se aplica **sólo** a los ítems `pendiente` y
  `en_curso`, por la misma razón que `rollback` no se reclama hacia atrás: un
  ítem cerrado no se va a mover de sitio y exigírselo sería ruido permanente.
  Aun así, un ledger en uso con una arista hacia adelante en un ítem por
  ejecutar pasará a fallar la validación. La corrección es mover el ítem después
  de su bloqueante, que es lo que el orden ya tenía que reflejar.
- El formato del ledger no cambia: no hay campos nuevos ni renombrados, así que
  `schema_version` sigue en 1.

## [1.10.0] — 2026-08-26

### Añadido
- **`arnes ver`: vista web del plan.** Página generada desde el ledger con
  Python, sin llamadas al modelo, con el avance por ola, los criterios de
  entrada y salida de cada una y la ficha completa de cada ítem —qué se hizo,
  cómo se verificó, cómo se revierte—. Los campos que el arnés no conoce se
  vuelcan al pie de cada ficha en lugar de descartarse: el esquema del ledger es
  abierto y ahí es donde acaban los hallazgos no previstos.
- **`arnes ver --live`.** Sirve la página en local y la recarga al cambiar el
  ledger. No requiere una ejecución previa de `arnes ver`: genera la página si
  no existe o si el ledger es más reciente, y mantiene el archivo en disco al
  día mientras corre. Un ledger a medio escribir devuelve un aviso en lugar de
  detener el servidor.
- **Compartir desde la propia página.** «Guardar copia» descarga la página
  serializada como un `.html` autocontenido —sin peticiones externas, abrible
  desde `file://`—; «Copiar resumen» deja el estado en texto en el portapapeles;
  «Imprimir o PDF» usa el diálogo del navegador, con hoja de estilos propia que
  omite los controles y despliega los campos plegados. La página se escribe en
  un directorio temporal, no en el proyecto: un artefacto generado dentro del
  repositorio obliga a decidir si se versiona.
- **`arnes docs`.** Abre la documentación en el navegador: por defecto la copia
  que acompaña a la versión instalada, y con `--web` la publicada. La dirección
  publicada se imprime siempre, para compartirla con quien no tiene el plugin.
- **`arnes validar`.** El validador del ledger deja de invocarse por su ruta.
  Acepta `--item` y `--al-cerrar`. Elimina el único punto donde la ayuda repartía
  una ruta con la versión dentro, que es la clase de ruta que sobrevive a una
  actualización y acaba ejecutando código anterior.
- **La página de presentación pasa a ser también referencia**, con índice de
  navegación y seis secciones nuevas: primeros pasos, comandos y variables de
  entorno, modos de supervisión, guardas, mensajes de consola y campos del
  ledger. El objetivo es poder usar el arnés sin abrir el repositorio.
- **Tablas de guardas y de mensajes en el README.** La información ya estaba en
  prosa; faltaba la forma consultable.
- **Aviso de ítems abiertos en `arnes ver`.** Los `en_curso` que no son el
  elegido se señalan aparte, con el comando para retomarlos.

### Corregido
- **La vista web elegía un ítem distinto del que ejecuta el lanzador.**
  Reproducía la regla del hook de arranque, que antepone cualquier `en_curso` a
  cualquier `pendiente`, mientras que `plan-run.sh` toma el primero en orden de
  fichero. Con un pendiente por delante de un ítem a medias, la página anunciaba
  uno y el lanzador ejecutaba otro. La vista pasa a reproducir la regla del
  lanzador.
- **La ayuda imprimía `$ARNES` sin resolver**, una variable que sólo existe en
  la cabecera de los scripts: copiar esas líneas devolvía «No such file or
  directory».
- **Documentación que no correspondía al comportamiento real.** Se corrigen diez
  afirmaciones, verificadas contra el código: `--igual` no salta las preguntas
  del modo interactivo, sólo la ficha incompleta, la negativa de
  `--desatendido` y las puertas de cierre; cancelar en una de esas preguntas
  sale con código 0 y no 1; la guarda de árbol sucio no cuenta los ficheros sin
  rastrear; el límite de la verificación es 900 s por el lanzador pero 120 s por
  defecto y 180 s de techo por el hook; el hook sólo dispara con las
  herramientas de edición de Claude Code y sólo sobre un fichero llamado
  `ejecucion-plan.estado.json`, y nunca devuelve código distinto de 0;
  `PLAN_LEDGER` no cae de vuelta a la búsqueda por rutas convencionales; el
  aviso de claves fuera de esquema no aparece al lanzar un ítem; y la tabla de
  campos omitía siete que sí son parte del esquema.
- **Registro de la documentación.** Se retiran de la página y del README los
  pasajes que narraban cómo se descubrió algo o para qué podía servir, en favor
  de la descripción del comportamiento.

### Cambiado
- Se documenta explícitamente que **`--auto` actúa sobre los permisos, no sobre
  las guardas**: un ítem lanzado así sigue deteniéndose a preguntar si está
  bloqueado, pide más de una hora de máquina o el árbol tiene cambios sin
  commitear. El comportamiento no cambia; faltaba enunciarlo.

### Notas de implementación
- La paleta de estados de la vista se validó con el comprobador de la guía de
  visualización en los dos temas: banda de luminosidad, croma, separación bajo
  daltonismo y contraste sobre la superficie. `pendiente` es neutro por diseño
  —es la pista sin rellenar de la barra, no un color de serie—. La separación
  bajo tritanopía queda bajo el umbral recomendado, lo que exige codificación
  secundaria: cada estado lleva punto y palabra, cada barra su fracción, y los
  segmentos van separados 2 px.
- El bloque de JavaScript de la vista vive en una cadena literal de Python. En
  una cadena normal, su `\n` se expandía a un salto de línea real dentro de un
  literal de JavaScript y rompía el script completo —los tres botones y el
  plegado— sin error visible en la página. Se usa cadena en bruto, y la suite
  comprueba tanto el escape como que el JavaScript compila.
- La suite comprueba que la documentación no se desincronice del código: cuenta
  las guardas declaradas en `plan-run.sh` y exige que la página y el README
  nombren cada una; verifica que toda cadena citada como salida de consola
  exista literalmente en el script; que los dos límites de verificación estén
  documentados; que ningún enlace del índice apunte a una sección inexistente; y
  que ninguna ruta ofrecida lleve la versión dentro.

## [1.8.2] — 2026-08-26

### Corregido
- **La página publicada anunciaba la versión anterior.** El número no se
  actualizó al publicar la 1.8.1. La comprobación introducida en esa misma
  versión lo detectaba, pero el cambio se integró sin revisar su resultado.
- **Una comprobación de la suite dependía del entorno.** El aviso de "copia no
  instalada" se contrasta con `installed_plugins.json`, que no existe en una
  máquina sin el plugin instalado: la comprobación pasaba en un equipo de
  desarrollo y fallaba en integración continua, señalando una diferencia de
  entorno en lugar de un cambio de comportamiento. Se ejecuta ahora contra un
  `HOME` propio, y se añade el caso complementario: sin registro de instalación
  no debe emitirse aviso alguno.

## [1.8.1] — 2026-08-26

### Cambiado
- Redacción del README en tono descriptivo. Cuatro pasajes justificaban una
  decisión de diseño narrando cómo se había detectado el problema; se sustituyen
  por la descripción del comportamiento y su motivo. Sin cambios de código ni de
  comportamiento.

## [1.8.0] — 2026-08-25

### Corregido
- **Instrucciones específicas de Unix en sistemas Windows.** Tras sembrar el
  ledger, el arnés indicaba instalar el lanzador en `~/.local/bin`, añadirlo al
  PATH con `export PATH=...` y validar con `python3`; ninguna de las tres es
  aplicable en PowerShell. `scripts/entorno.sh` centraliza ahora lo que varía
  entre sistemas —intérprete de Python y sintaxis de PATH— y el resto de scripts
  lo consulta. En Windows se instala además `arnes.cmd`, ya que PowerShell y
  `cmd` no ejecutan scripts de bash. El hook deja de fijar el intérprete.

  El soporte de Windows depende de git-bash o WSL y no está verificado de
  extremo a extremo; el README lo indica.
- **Código de salida indeterminado en `arnes --help`.** Lo definía el último
  comando ejecutado, que varía según la rama del script y el sistema operativo,
  con fallos intermitentes en integración continua. Devuelve 0 explícitamente.
- **Versión desactualizada en la página de presentación.** El número está
  escrito en el HTML y no se sincronizaba con el manifiesto. La suite verifica
  ahora que ambos coincidan.

## [1.7.0] — 2026-08-25

### Añadido
- **La página de presentación se renderiza fuera del visor de artifacts.**
  Incluye su propio motor de Mermaid, por lo que es publicable en GitHub Pages y
  legible como adjunto. Dentro del visor la carga externa queda bloqueada por
  CSP y los diagramas los renderiza el propio visor; sin conectividad se
  degradan a texto.

### Cambiado
- `docs/como-funciona.html` pasa a `docs/index.html`, para que la URL publicada
  sea la raíz del sitio.

## [1.6.1] — 2026-08-25

### Corregido
- **El hook de arranque publicaba una ruta con la versión fijada.** Claude Code
  conserva las versiones anteriores del plugin, por lo que una sesión abierta
  antes de una actualización seguía ofreciendo una ruta ejecutable a código
  obsoleto. Ahora indica el lanzador `arnes`, que resuelve la instalación en
  cada ejecución, o el comando para instalarlo.
- `plan-run.sh` advierte cuando la copia en ejecución no es la instalada. No
  bloquea: ejecutar una copia concreta es un caso legítimo.

## [1.6.0] — 2026-08-25

### Añadido
- **`arnes --help`.** Antes delegaba en la cabecera de `plan-run.sh`, que
  documenta sus banderas pero no los verbos del lanzador, las variables de
  entorno ni los slash commands. La ayuda ocupa una pantalla y termina con el
  proyecto, el ledger y el ítem siguiente. Reside en el plugin, de modo que se
  actualiza con él; el lanzador recurre a `plan-run.sh --help` si el plugin
  instalado es anterior.

## [1.5.3] — 2026-08-25

### Corregido
- **El protocolo indicaba un comando inexistente.** El paso 6 pedía "el comando
  exacto para continuar" sin especificarlo, y se resolvía con la forma corta. El
  comando figura ahora literal. La suite falla si cualquier fichero de
  `commands/`, `scripts/`, `hooks/` o `plantillas/` documenta la forma corta; el
  patrón distingue el comando de una ruta.

## [1.5.2] — 2026-08-25

### Corregido
- **`--desatendido` no completaba la ejecución.** Usaba
  `--permission-mode acceptEdits`, que sólo aprueba ediciones; la lectura del
  ledger es una llamada de shell que quedaba a la espera de una aprobación
  imposible en modo `-p`. Usa `bypassPermissions`, el único modo con el que la
  cadena se completa. Es una elevación de permisos real, y justifica que este
  modo mantenga las guardas más estrictas —más de una hora de máquina,
  multiagente, `opus`, ítem bloqueado o árbol sucio— y techo de gasto
  obligatorio.

## [1.5.1] — 2026-08-25

### Corregido
- **La sesión nueva se lanzaba con un comando inexistente.** Los slash commands
  de un plugin residen en su propio espacio de nombres, por lo que
  `/plan-siguiente` responde `Unknown command` y la sesión se abría sin efecto.
  El nombre se lee del manifiesto, de modo que renombrar el plugin no reintroduce
  el fallo.

  La suite no lo detectaba: sustituye `claude` por un doble que acepta cualquier
  cadena. La regresión verifica ahora la cadena que se pasa, no la ausencia de
  error.
- La línea del hook y la documentación indicaban también la forma corta.

## [1.5.0] — 2026-08-25

### Añadido
- **Puerta de cierre como hook `PostToolUse`**, asociada a la escritura del
  ledger en lugar de a un comando concreto. Con independencia de la vía por la
  que se cierre un ítem, si acaba de pasar a `hecho` se comprueba que tenga
  `resultado` y que su `verificacion_comando` devuelva 0. Sólo evalúa los ítems
  recién cerrados, comparando con el ledger en `HEAD`.

  Hasta esta versión las comprobaciones sólo se ejecutaban desde `plan-run.sh`,
  mientras que el flujo habitual es `/plan-siguiente`, donde el protocolo se
  limitaba a solicitar la autoevaluación del agente.
- **Aviso de campos fuera del esquema**, en el validador y en la puerta de
  cierre. No invalida el ledger, pero un campo no documentado no lo lee ninguna
  herramienta. Un prefijo `_` exime del aviso.
- La plantilla documenta qué escribir en `rollback` cuando la reversión no es
  posible: la mitigación, o el motivo por el que no aplica.

### Corregido
- **El plugin publicaba un ledger propio.** Ejecutar `arrancar.sh` con este
  repositorio como raíz sembraba `docs/plan/ejecucion-plan.estado.json` en él.
  Eliminado, con `.gitignore` y comprobación en la suite.
- El protocolo indicaba añadir los ítems nuevos al final de su ola. Los cierres
  simultáneos se fusionan sin conflicto incluso entre ítems contiguos; el
  conflicto real se produce al añadir al mismo final. Se inserta por orden de id.

## [1.4.0] — 2026-08-25

### Añadido
- **`/arnes-plan:plan-arrancar`**, puesta en marcha sin rutas ni variables de
  entorno.
- **Lanzador `arnes`** en `~/.local/bin`, el directorio del propio ejecutable
  `claude`. No fija ninguna ruta: resuelve la instalación en cada ejecución. No
  sobrescribe un `arnes` preexistente; `--sin-atajo` omite su instalación.

### Corregido
- **El lanzador podía ejecutar una versión no instalada.** El respaldo para
  cuando `claude` no está en el PATH elegía la versión más alta del cache, que
  incluye instalaciones anteriores y versiones nunca activadas. Ahora lee
  `installed_plugins.json`.

## [1.3.0] — 2026-08-25

### Corregido
- **La puesta en marcha documentada podía sobrescribir un ledger existente.**
  Indicaba copiar la plantilla sobre `ejecucion-plan.estado.json`, de modo que
  un segundo desarrollador que siguiera el README reemplazaba el plan del
  primero. `arrancar.sh` detecta si ya existe un plan y nunca sobrescribe: lo
  valida y anuncia el ítem siguiente. Es idempotente.
- **El README indicaba obtener la ruta de instalación con `claude plugin list`**,
  que no la proporciona; requiere `--json`. Se documenta la resolución de
  `$ARNES` mediante el CLI en lugar de fijar un número de versión.
- Documentado que `claude plugin update` requiere el nombre cualificado
  (`arnes-plan@arnes-plan`).

### Añadido
- `scripts/arrancar.sh`: puesta en marcha en un solo comando, que imprime al
  finalizar la línea de `export ARNES` ya resuelta.

## [1.2.0] — 2026-08-25

### Añadido
- **Diagramas del arnés en el README**, renderizados por GitHub: la secuencia de
  una invocación, con las puertas de cierre fuera de la sesión que ejecuta el
  trabajo, y el ciclo de vida de un ítem con la condición de cada transición.
- `docs/como-funciona.html`, la misma explicación como página.
- `scripts/validar-diagramas.py`: el mismo Mermaid reside en dos ficheros porque
  cada uno sirve a un público distinto, y dos copias divergen. La suite falla si
  dejan de coincidir. Compara los diagramas, no el documento: la página tiene
  prosa propia.

## [1.1.0] — 2026-08-25

El estado `hecho` lo escribe el mismo agente que ejecuta el ítem, por lo que no
constituye evidencia por sí solo. Esta versión añade dos comprobaciones de
cierre independientes de esa declaración.

El esquema del ledger permanece en la versión 1: `verificacion_comando` es un
campo que un lector anterior ignora. Con la salvedad de que lo ignora en
silencio: un arnés 1.0.x sobre un ledger que lo use no ejecutará la verificación.

### Añadido
- **`verificacion_comando`**, campo opcional del ítem: la parte de
  `verificacion` que puede decidirse mecánicamente. `plan-run.sh` la ejecuta en
  la raíz del proyecto una vez finalizada la sesión, con límite de tiempo
  configurable (`ARNES_LIMITE_VERIFICACION`, 900 s por defecto).
- **`resultado` obligatorio al cerrar.** Se exige en el momento del cierre
  (`validar-ledger.py --al-cerrar`) y no en la validación general, por el mismo
  criterio que `rollback`: no se reclama a trabajo ya cerrado.
- Ninguna de las dos puertas revierte cambios: el script devuelve un código
  distinto de 0 y muestra el motivo.
- **Techo de reintentos y parada por ficha incompleta** en el protocolo del
  comando: tres intentos sobre una verificación en rojo; una ambigüedad
  originada en la ficha detiene la ejecución sin intentos previos.

### Corregido
- **`--desatendido` aceptaba ítems marcados `opus`.** Las guardas evaluaban
  horas de máquina, multiagente y bloqueo, pero no el modelo. `--igual` la
  omite, como las demás.
- La plantilla del ledger referenciaba `infra/arnes/`, ruta anterior a la
  distribución como plugin.

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

[1.15.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.14.0...arnes-plan--v1.15.0
[1.14.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.13.1...arnes-plan--v1.14.0
[1.13.1]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.13.0...arnes-plan--v1.13.1
[1.13.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.12.2...arnes-plan--v1.13.0
[1.12.2]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.12.1...arnes-plan--v1.12.2
[1.12.1]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.12.0...arnes-plan--v1.12.1
[1.12.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.11.0...arnes-plan--v1.12.0
[1.11.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.10.0...arnes-plan--v1.11.0
[1.10.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.8.2...arnes-plan--v1.10.0
[1.8.2]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.8.1...arnes-plan--v1.8.2
[1.8.1]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.8.0...arnes-plan--v1.8.1
[1.8.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.7.0...arnes-plan--v1.8.0
[1.7.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.6.1...arnes-plan--v1.7.0
[1.6.1]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.6.0...arnes-plan--v1.6.1
[1.6.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.5.3...arnes-plan--v1.6.0
[1.5.3]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.5.2...arnes-plan--v1.5.3
[1.5.2]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.5.1...arnes-plan--v1.5.2
[1.5.1]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.5.0...arnes-plan--v1.5.1
[1.5.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.4.0...arnes-plan--v1.5.0
[1.4.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.3.0...arnes-plan--v1.4.0
[1.3.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.2.0...arnes-plan--v1.3.0
[1.2.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.1.0...arnes-plan--v1.2.0
[1.1.0]: https://github.com/DanielWueno/arnes-plan/compare/arnes-plan--v1.0.0...arnes-plan--v1.1.0
[1.0.0]: https://github.com/DanielWueno/arnes-plan/tree/arnes-plan--v1.0.0
