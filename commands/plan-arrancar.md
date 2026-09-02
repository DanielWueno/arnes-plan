---
description: Deja el arnés listo en este proyecto y instala el atajo `arnes` en la terminal
---

Ejecuta, sin preguntarme nada primero:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/arrancar.sh"
```

Existe para que poner en marcha el arnés no exija que nadie busque una ruta a mano: aquí
`${CLAUDE_PLUGIN_ROOT}` ya viene dado, así que este comando funciona recién instalado el plugin,
sin variables de entorno ni copiar nada del README.

El script decide él lo que toca, y **nunca sobrescribe un ledger que ya exista** — si este
repositorio ya tiene plan, valida el que hay y anuncia el ítem siguiente. También instala el
lanzador `arnes` en `~/.local/bin`, que es donde vive el propio `claude`.

Después, muéstrame su salida tal cual y resume en dos líneas:

1. Si se sembró un plan nuevo o ya había uno (y en qué ruta).
2. Qué hago ahora: escribir mis ítems si el plan es nuevo, o el comando exacto para ejecutar el
   siguiente si ya había plan.

En Windows el script registra `~/.local/bin` en el PATH de usuario por su cuenta; dime que hay que
abrir una consola nueva para que surta efecto. Si avisa de que no ha podido —o estás en Unix y la
carpeta falta en el PATH—, dame la línea que hay que añadir al perfil del shell, que es entonces lo
único que no puede arreglar él solo.

No ejecutes ningún ítem del plan. Este comando prepara; no trabaja.
