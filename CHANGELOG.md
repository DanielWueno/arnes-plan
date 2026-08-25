# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado: [SemVer](https://semver.org/lang/es/).

El **mayor** cambia cuando cambia el formato del ledger, porque eso obliga a
tocar los ledgers en uso. Un menor añade campos que un lector viejo ignora.

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
