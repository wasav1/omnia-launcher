# Referencia del prototipo Estantería y adaptación a Omnia

Fecha de revisión: 2026-11-15. Fuente local: `/home/wsaenz/Juegos/PROTOTIPO OMNIA/`.
Este documento registra lo observado; no implica que las funciones pendientes ya estén implementadas.

## Material revisado y prioridad

- Siete capturas numeradas de la estantería, filtro PC, menú contextual, Big Menu, energía, búsqueda y selector de arte.
- Dos capturas adicionales: escritorio completo con panel/dock y Ocarina con dos ports y seis ranuras.
- Documento PDF de contexto de 33 páginas: distribución, interacción, arquitectura, integraciones y decisiones heredadas.
- Prototipo HTML y MangoHud.conf localizados como recursos complementarios; su contenido no se ha auditado todavía.
- Respaldo-Sistema: archivos tar.gz, diseños Konsave, tema de bienvenida/bloqueo, SVG y fuentes.

Prioridad para reconstruir: capturas del 15/11 para el aspecto; código ya conservado en el repo para la lógica más reciente;
archivos comprimidos para recuperar piezas concretas. No restaurar un escritorio completo de Bazzite sobre CachyOS.

**Versiones diferentes:** `estanteria-20261114.tar.gz` y `respaldo-completo-20261114/configuracion-y-widgets.tar.gz`
contienen main.qml de 1.518 líneas y helper.py de 943; los del repo tienen 2.403 y 1.651 respectivamente.
Ambos archivos difieren de los respaldos. Esto impide tratar los tar como una copia exacta de las capturas.
No se han ejecutado scripts de restauración ni instalado bibliotecas .so del respaldo.

## Especificación visual observada

Referencia de escritorio: 1920 × 1080. Adaptar con márgenes y tamaños responsivos a otras resoluciones y al escalado.

- Cabecera: filtros Todos, Favoritos y plataformas presentes; búsqueda, energía y refresco. Píldoras de fondo transparente,
  borde fino y estado activo claro. Colores por plataforma, sin inventar categorías donde no hay juegos.
- Izquierda: origen/plataforma, estado, logo del juego (título como alternativa), descripción, chips, selector de port y Jugar.
- Centro: reloj grande AM/PM y fecha; insignia del mando; ranuras con fechas; ficha con última sesión, espacio en disco,
  ajustes y último respaldo. No mostrar cifras de ejemplo como si fueran mediciones reales.
- Derecha: reproductor MPRIS (título, artista, controles, progreso); métricas CPU, GPU, RAM, VRAM, disco y batería;
  historial de temperatura CPU de 60 s. Es un panel lateral, no el widget Anillos que se descartó.
- Abajo: tarjetas verticales, seleccionada elevada y grande (~290×435), resto ~190×285, origen, favorito, nuevo y número
  de ports. Mantener creación de delegados acotada a la zona visible.
- Fondo: arte del juego oscurecido con transición, paleta de acento por juego, paneo lento opcional y ondas inferiores.
  Pausar animaciones cuando estén tapadas; ofrecer reducción de movimiento.
- Material: cristal verde casi negro, texto hueso #f3efe3, dorado #e6d9a0; bordes suaves de 1 px. Profundidad por velos
  y desenfoque, sin añadir sombras pesadas.
- Tipografías documentadas: Noto Sans (texto), Rajdhani (etiquetas/cifras), Hanken Grotesk (reloj). Comprobar licencias y
  disponibilidad antes de distribuir fuentes. Usar alternativas cuando falten.

## Diferencias y trabajo pendiente

| Área | Omnia actual | Recuperar del prototipo |
|---|---|---|
| Estantería | Fila centrada, ficha abajo y reloj pequeño | Composición izquierda/centro/derecha, fila inferior y tarjeta elevada |
| Filtros y búsqueda | Datos de plataforma/favoritos/ocultos en API; UI básica | Píldoras, búsqueda de juegos, filtro Ocultos y refresco visibles |
| Arte | Descarga de portada y fondo | Logos, elección manual de portada/fondo/logo, estado En uso, ediciones |
| Ports | Backend admite varios; UI usa el primero; importador los divide | Selección de port por juego y LT/RT; conservar ids e historial al agrupar |
| Partidas/historial | Motor, panel y sesiones implementados | Resumen de ranuras y ficha integrada; mantener el panel completo existente |
| Menú contextual | Acciones repartidas en botones/paneles | Menú de juego con jugar, partidas, carpeta, arte, favorito y ocultar |
| Big Menu | Búsqueda, grupos, favoritos, teclado y mando | Panel de ~900×690 a 1080p, seis columnas, favoritos como sección, mosaicos coloreados y animación |
| Energía | Sin menú dedicado | Bloquear, suspender, cerrar sesión, reiniciar y apagar; confirmar las tres últimas |
| Multimedia/sistema | Sin servicios específicos en core | MPRIS, telemetría y audio por módulos; datos no disponibles con estado explícito |
| Mando | evdev y foco validados | Navegación por zonas, guía de botones, teclado virtual y controles documentados por pantalla |
| Panel/dock | Plasma actual; widgets antiguos conservados como referencia | Estilo y disposición opcionales de Plasma, menú global, bandeja y gestor de tareas nativos |

Los controles de las capturas difieren de Omnia actual: SELECT hoy abre Añadir juego, X abre Partidas, Y marca favorito y
LB/RB saltan juegos. No cambiarlos parcialmente: definir el mapa completo y actualizar pistas y pruebas en el mismo paso.
El prototipo usa Start para Big Menu, SELECT para contexto/energía, LB/RB para filtros y LT/RT para ports.

La API actual no expone aún todos los campos del prototipo (logo, paleta, chips, selección de port, ajustes, métricas).
Ampliar el contrato antes de diseñar componentes que dependan de esos datos. Los fallbacks deben funcionar con Steam,
Heroic, Lutris y entradas manuales sin esos campos.

## Orden de implementación

1. **Paridad visual de la estantería.** Separar componentes (filtros, ficha, reloj/ranuras, tarjetas, fondo), exponer metadatos
   necesarios y conservar la selección por id al refrescar/filtrar. Logos con fallback al título. Primer corte con datos
   reales y huecos omitidos donde aún no hay servicios, sin valores ficticios.
2. **Interacción de biblioteca.** Búsqueda, favoritos/ocultos, menú contextual, selector de arte y múltiples ports. Agrupación
   explícita y reversible para tarjetas importadas; no fusionar solo por parecido del nombre.
3. **Panel lateral vivo.** MPRIS, métricas, gráfica, salida de audio y ondas. Muestreo acotado, pausa y presupuesto de CPU.
4. **Big Menu y mando.** Paridad visual, energía con confirmación, teclado virtual, guía y navegación por zonas.
5. **Tema/layout instalable de KDE, después de validar Omnia.** Esquema de colores, apariencia Plasma, panel superior y dock
   nativos, integración de botón Omnia y bienvenida opcional. Un solo repo con piezas instalables separadas.

## Condiciones para el futuro tema/layout

- El launcher conserva su proceso QML y el servicio propios; el tema visual no sustituye esas funciones.
- Panel superior y dock se basan en Plasma: conservar bandeja, menú global y gestor de tareas nativos.
- Instalación por usuario, vista previa/consentimiento al cambiar el layout, respaldo y restauración del diseño anterior;
  repetir el instalador no duplica paneles. Identificar paneles propios, nunca usar ids heredados 218/242.
- Efectos KWin compilados son opcionales y requieren compatibilidad con el KWin actual. Las .so de Bazzite no se instalan.
- Bloqueo propio no estaba instalado en el prototipo: mantener el de Plasma hasta una revisión independiente.
- Anillos permanece excluido. El panel lateral del sistema sí forma parte de la referencia de Omnia.
- Revisar permisos/licencias de fuentes, iconos y logos antes de distribuir. El arte descargado por el usuario se mantiene
  fuera del paquete y del repositorio.

## Verificación por etapa

- Capturas comparables a 1920×1080 y revisión a una resolución menor; comprobar que panel/dock no tapan controles.
- Teclado, clic y mando en estantería, menús y búsquedas; conservar Meta, Meta+D y el bloqueo de entrada con ventanas encima.
- Sin perder biblioteca, preferencias, historial ni rutas de partidas; migraciones con copia y posibilidad de volver atrás.
- Pruebas funcionales acordes al cambio, qmllint y lanzamiento de la UI aislada antes de actualizar servicios instalados.
- Medir CPU/memoria con la vista visible y tapada; comprobar que la lista no crea una tarjeta por toda la biblioteca.

## Inventario de referencias (SHA-256)

Estos archivos permanecen fuera del repo; hashes para saber exactamente qué referencia se revisó.

| Archivo | Bytes | SHA-256 |
|---|---:|---|
| 01-estanteria.png | 1387320 | `db92a054bd7844264041328f677eccf53d1cc8e5de233b5341451be5b42970f4` |
| 02-filtro-pc.png | 1371420 | `17c34f3b0c94dc2370d247f03db2ba5737dde109a153fdbf2ddc8766ae37fdc6` |
| 03-menu-contextual.png | 1675759 | `ad642ce1d249608e99a094eebc7d495b9dd20423ab09cc1df088b76eb41abb2d` |
| 04-big-menu.png | 1307716 | `114329ea3b93aa0f8ae03d111f510b55f1656925017bd0ef11a0c4a5eaa10774` |
| 05-energia.png | 1237483 | `e795a5e16b67e9314a097f74af8bbcb0837551219629add8de563756b29cdbe2` |
| 06-busqueda.png | 1272729 | `c703970468d1bc9651c5d9e16b99fa2d5273f03b3e215c4bb4ddbe3491a2844e` |
| 07-selector-arte.png | 1929209 | `1468df13d4f06421434ea45277ec2c7134a878c1b911b87915c33a2f0dce0866` |
| Captura de pantalla_20261115_171240.png | 1422541 | `fd0cf4c04c420e3b10525b272a4e6b8f528b79f6c60072e90f7fd01cd91e6a53` |
| Captura de pantalla_20261115_171749.png | 1889057 | `125ffbe10bbd01dc3e247b43a57d4653a0a79dfe5e029377ec7f262d4f771775` |
| Estantería de juegos para KDE Plasma — contexto completo del proyecto.pdf | 9847359 | `c091ccbbdc745d0aee1330c31ef7919c0a959d677ee34fea79b8e8b5136d2c47` |
| prototipo-acceso-estanteria.html | 37784 | `60be1e08da20387584b08e3c25b7bfdc814f2926b48de7a376f511ba28f30693` |
| MangoHud.conf | 806 | `4d5dc13901f8451d1a528c5100031d9cd168088c78266e999aed64afc123fb86` |
