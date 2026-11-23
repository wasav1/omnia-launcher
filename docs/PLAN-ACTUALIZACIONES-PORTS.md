# Plan · Fase 3: actualizaciones de ports instalados

Fecha: 2026-11-23. Estado: **implementada (2026-11-23)**; pendiente de prueba real con un port que publique una versión nueva. Decisiones del usuario: superponer sobre la carpeta actual, comprobar cada 6 h (`catalog_packages` ya se refresca así), y la tarea del backend que detecta releases queda para después.
Continúa `docs/PLAN-INSTALACION-AUTOMATICA-PORTS.md` (§4.4, «Actualización disponible»).

## 1. Objetivo

Cuando un port instalado desde el catálogo tiene una versión nueva publicada, Omnia lo avisa («Actualización disponible») y el usuario
la instala con un clic o con el mando, **sin perder partidas ni archivos del juego que el propio port preparó**.

## 2. Qué ya existe (punto de partida)

- Cada instalación guarda `installPackageId`, `installVersion`, `installPath` y `catalogSlug` en la ficha del juego, y
  `package-installs.json` guarda `{gameId, packageId, catalogSlug, version, path, entrypoint}`.
- `GET /catalog/install-packages?slug=…` devuelve los paquetes publicados de una ficha (cada uno con `version`, `sha256`, `sizeBytes`…).
- `PackageInstallManager` ya descarga con SHA-256, extrae de forma segura y registra el juego.

## 3. Qué es «versión nueva»

Las versiones del catálogo son etiquetas libres («0.1.17», «v3.1.1»…), así que **no se comparan numéricamente**.
Hay actualización cuando, para el mismo `catalogSlug`, existe un paquete publicado con `id` distinto al instalado **y** más reciente
según el orden en que el catálogo lo devuelve (el más nuevo primero). Si hay varios paquetes publicados de la misma ficha
(p. ej. otra plataforma o formato), solo cuenta el que coincide en `archiveFormat`/`entrypoint` con el instalado.
El catálogo ya expone `createdAt`; las instalaciones nuevas guardan `publishedAt` y `archiveFormat`. Si el paquete instalado dejó de estar publicado, solo se ofrece uno más nuevo que `publishedAt` (nunca bajar de versión).

## 4. Pasos

1. **Detección (núcleo).** Nuevo `package_updates.py`: al arrancar y cada 6 h (y a petición) consulta los paquetes de las fichas con
   instalaciones, compara y guarda el resultado en `state.json` (`package_updates`, con hora de la última comprobación). Sin red: no
   muestra nada nuevo y no falla. `/library` añade `updateAvailable: {packageId, version, sizeBytes}` por juego.
2. **Instalar encima, sin perder datos.** `start(..., update_of=gameId)`: descarga y extrae a la zona temporal como hoy; después **superpone** la
   versión nueva sobre la carpeta existente: solo se reemplazan los archivos que trae el paquete y se conserva todo lo demás
   (Longshot guarda el juego construido en `Longshot/`; otros ports guardan datos fuera de la carpeta, p. ej. `~/.local/share/mkw-recomp`).
   Antes de reemplazar, cada archivo sustituido se mueve a `.omnia-previo/` dentro de la carpeta; si algo falla, se restaura y se
   conserva la versión anterior. Al terminar con éxito se borra `.omnia-previo/` y se actualizan `installVersion`/`installPackageId`/registro.
   No se crea otro juego ni se toca la ficha, el arte, el tiempo jugado ni las partidas.
3. **Seguridad y reglas.** Mismas reglas que la instalación (HTTPS público, SHA-256, extracción segura, carpeta dentro de las raíces permitidas).
   No se actualiza mientras el juego esté en ejecución. El enlace simbólico o la carpeta ausente cancelan la actualización.
4. **Interfaz.** Etiqueta «Actualización disponible» en tarjeta y ficha; acción «Actualizar» (menú contextual, ficha, panel rápido y
   Big Mode, con mando); diálogo con versión actual → nueva, tamaño y fuente; progreso en Instalaciones. Nunca se actualiza sin confirmar.
5. **Ajuste.** Interruptor «Buscar actualizaciones de ports» (activo por defecto) en la app de escritorio.
6. **Pruebas.** Tests de comparación (misma versión, nueva, paquete retirado, sin red), de la superposición (conserva archivos extra,
   restaura ante fallo, rechaza `..` y enlaces) y de la API; prueba real con una actualización de un port pequeño. Registro en `CONTEXTO.md`.

## 5. Riesgos y decisiones

- **Quién publica versiones nuevas.** Hoy el catálogo se actualiza a mano con `tools/release-packages` (backend). Sin una tarea que detecte
  releases nuevas de GitHub, el aviso solo aparece cuando alguien publica el paquete nuevo. Propuesta: tarea aparte en el backend
  (fuera de esta fase) que lea las releases de cada port y cree el paquete en `draft` para revisarlo.
- **Un port que cambia de estructura** entre versiones podría dejar archivos viejos; se acepta (se prefiere conservar datos a borrar de más).
- **Rollback manual:** mientras exista `.omnia-previo/` (solo durante la actualización) no hay copia de la versión anterior después de terminar.

## 6. Decisiones que necesito de ti

1. ¿Superponer sobre la carpeta actual (propuesto) o instalar la nueva versión en otra carpeta y borrar la vieja?
2. ¿Comprobación automática cada 6 h (propuesto) o solo cuando abres la ficha?
3. ¿Incluyo ahora la tarea del backend que detecta releases nuevas, o la dejamos para después?
