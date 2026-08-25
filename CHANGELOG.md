# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado: [SemVer](https://semver.org/lang/es/).

El **mayor** cambia cuando cambia el formato del ledger, porque eso obliga a
tocar los ledgers en uso. Un menor añade campos que un lector viejo ignora.

## [1.6.1] — 2026-08-25

### Corregido
- **El hook de arranque repartía una ruta con la versión clavada dentro.**
  Imprimía `bash …/arnes-plan/1.2.0/scripts/plan-run.sh`, y Claude Code conserva
  las versiones viejas: una consola abierta antes de actualizar seguía ofreciendo
  un camino directo a código obsoleto, que se copia y se ejecuta. Pasó de verdad,
  con un `plan-run.sh` de cinco versiones atrás lanzando un comando ya inválido —
  y el fallo aparecía dentro de la sesión nueva, lejos de su causa. Ahora ofrece
  `arnes`, que resuelve la instalación en cada ejecución; y si no está instalado,
  la línea para instalarlo.

  Era el último sitio del arnés que clavaba una versión: la enfermedad que este
  plugin lleva toda la 1.4 y la 1.5 curando, en el rincón donde quedaba.
- `plan-run.sh` avisa cuando la copia que se ejecuta no es la instalada. No
  bloquea —correr una copia a propósito es legítimo— pero deja de ser silencioso.

## [1.6.0] — 2026-08-25

### Añadido
- **`arnes --help`**, que ahora contesta de verdad. Antes reenviaba a la
  cabecera de `plan-run.sh`: documentaba sus banderas, pero enseñaba la forma
  larga que el atajo existe para sustituir, y no mencionaba ni los verbos de
  `arnes`, ni las variables de entorno, ni los slash commands. Todo eso vivía
  sólo en el README, que es documentación — hay que ir a buscarla, y en una
  terminal nadie la busca.

  La ayuda cabe en una pantalla y termina con **el estado real**: proyecto,
  ledger y el ítem que toca. Una ayuda que además contesta "¿y dónde estoy?" se
  consulta; una que recita banderas, no. Vive en el plugin y no en el lanzador,
  así que se actualiza con él; el lanzador cae a `plan-run.sh --help` si el
  plugin instalado es más viejo que el atajo, en vez de contestar con un error
  de bash.

## [1.5.3] — 2026-08-25

### Corregido
- **El propio protocolo le enseñaba al usuario un comando que no existe.** El
  paso 6 pedía "el comando exacto para continuar" sin decir cuál era, así que el
  agente se lo inventaba en su forma corta, el usuario lo copiaba y se estrellaba
  con `Unknown command`. Ahora el comando va escrito literal en el protocolo.

  Es la cuarta vez que muerde el mismo patrón —texto que da por sabido el espacio
  de nombres del plugin—, así que en vez de arreglar la cuarta se cubre la clase
  entera: la suite falla si CUALQUIER fichero de `commands/`, `scripts/`,
  `hooks/` o `plantillas/` enseña la forma corta. El patrón distingue el comando
  de una ruta, para no confundirse con `scripts/plan-siguiente-linea.py`.

## [1.5.2] — 2026-08-25

### Corregido
- **`--desatendido` abría la sesión y no hacía nada.** Pedía
  `--permission-mode acceptEdits`, que sólo aprueba EDICIONES; pero el protocolo
  empieza leyendo el ledger con un script, y en modo `-p` esa llamada de Bash se
  quedaba esperando una aprobación que nadie podía dar. Ahora usa
  `bypassPermissions`, que es el único modo con el que la cadena se completa
  —`dontAsk` tampoco basta, medido contra un `claude` real—. Es una escalada de
  permisos de verdad, y queda documentada junto a las guardas que la justifican:
  este modo se niega ante más de una hora de máquina, multiagente, `opus`, un
  ítem bloqueado o un árbol sucio, y exige techo de gasto.

Con esto el arnés completa un ítem de principio a fin por primera vez desde que
se extrajo a plugin: trabajo hecho, ítem cerrado con `resultado`, un solo commit
con trabajo y ledger, y las dos puertas de cierre disparando.

## [1.5.1] — 2026-08-25

### Corregido
- **`plan-run.sh` arrancaba la sesión nueva con un comando que no existe.** Los
  slash commands de un plugin viven en el espacio de nombres del plugin, así que
  `/plan-siguiente` responde `Unknown command`: la sesión se abría y no hacía
  nada. Es la función principal del arnés, y estuvo rota desde que se extrajo a
  plugin. El nombre se lee ahora del manifiesto, para que renombrar el plugin no
  vuelva a romperlo en silencio.

  Lo tapaba la propia suite: sus pruebas sustituyen `claude` por un doble que
  acepta cualquier cadena, así que el comando inválido pasaba verde. La
  regresión ahora comprueba **la cadena que se le pasa**, no que no reviente —
  un doble de prueba sólo verifica lo que se le pide verificar.
- La línea del hook de arranque y toda la documentación anunciaban también la
  forma corta, que era el primer tropiezo de cualquiera que llegara nuevo.

## [1.5.0] — 2026-08-25

Las puertas de cierre de la 1.1.0 sólo corrían por una de las dos entradas.
Vivían en `plan-run.sh`, pero el flujo diario es `/plan-siguiente` dentro de una
sesión, y por ahí el protocolo se limitaba a PEDIRLE al agente que se
autoevaluara — el fallo exacto que esa versión decía haber cerrado,
sobreviviendo en la otra puerta. Se vio en el único consumidor real:
`verificacion_comando` estaba en 0 de 57 fichas y cuatro ítems llegaron a
`hecho` sin `resultado`, parcheados a posteriori.

### Añadido
- **La puerta de cierre como hook `PostToolUse`**, enganchada a la escritura del
  ledger y no a un comando. Da igual quién cierre el ítem: si acaba de pasar a
  `hecho`, se comprueba que dejó `resultado` y que su `verificacion_comando`
  sale 0 corriéndolo ahí. El motivo le llega a Claude en el momento de la
  infracción, no tres pasos después con el commit ya escrito. Sólo mira lo que
  ACABA de cerrarse, comparando con el ledger en `HEAD`: nada retroactivo.
- **Aviso de campos fuera del esquema**, en el validador y en la puerta. No
  falla —el ledger es del proyecto— pero lo que se escribe en un campo
  inventado no lo lee nadie: en el consumidor real eran 53 nombres, la mitad
  usados una sola vez, con el validador diciendo `✓ Ledger válido`. Un `_`
  delante exime del aviso.
- La plantilla explica qué escribir en `rollback` cuando revertir no es
  posible: nombrar la mitigación, o por qué no aplica. `n/a` a secas no.

### Corregido
- **El plugin publicaba un ledger propio.** Probar `arrancar.sh` con este
  repositorio como raíz sembró `docs/plan/ejecucion-plan.estado.json` aquí
  dentro, y un `git add -A` lo publicó en la 1.4.0. Eliminado, con `.gitignore`
  y una comprobación en la suite, porque un `.gitignore` protege del descuido
  pero no de un `git add -f`.
- El protocolo pedía añadir los ítems nuevos al final de su ola. Medido: los
  cierres simultáneos fusionan solos incluso entre ítems contiguos, y lo único
  que hace chocar el ledger de verdad es justo eso — dos personas añadiendo al
  mismo final. Ahora dice que se inserte por orden de id.

## [1.4.0] — 2026-08-25

La 1.3.0 arregló que la instalación pudiera destruir un plan, pero seguía
pidiéndole al recién llegado que resolviera una ruta a mano y la guardara en
una variable de entorno. Eso no es instalar: es trabajo manual con otro nombre,
y encima caduca en cada actualización.

### Añadido
- **`/plan-arrancar`**, la puesta en marcha sin rutas ni variables. Dentro de
  una sesión el plugin ya sabe dónde está, así que funciona recién instalado.
- **El lanzador `arnes`**, que `arrancar.sh` deja en `~/.local/bin` —donde vive
  el propio `claude`, así que ya está en el PATH de quien tiene Claude Code—.
  No clava ninguna ruta: resuelve la instalación en cada ejecución y sobrevive
  a los `claude plugin update` sin tocarlo. No sobrescribe un `arnes` ajeno que
  ya estuviera en el PATH, y `--sin-atajo` lo omite.

### Corregido
- **El lanzador podía ejecutar una versión que no era la instalada.** El
  respaldo para cuando `claude` no está en el PATH elegía la versión más alta
  del cache, y ahí quedan tanto las instalaciones viejas como versiones que
  nunca llegaron a activarse. Ahora lee `installed_plugins.json`, que es lo que
  el propio CLI escribe. Correr en silencio código que no está activo es justo
  el fallo que este arnés existe para no cometer.

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
