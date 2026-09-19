# Integración de los siguientes bloques P2/P3

Fecha: 19 de septiembre de 2026. Rama: `feature/portable-clients`.
Base de esta revisión: `298c48b`.
Estado: plan propuesto; estas funciones todavía no están implementadas en el cliente portable.

## Objetivo y punto de partida

Completar funciones de extremo a extremo: motor Swift, persistencia, interfaz,
botón físico y paquete comprobado. Mantener la interfaz SwiftUI y el calendario
de Mac; compartir las reglas sin copiar su lógica a JavaScript. Trabajar y publicar
en la rama portable. Este plan no autoriza una fusión en `main`.

Ya funcionan disponibilidad manual, brillo, persistencia, panel, transporte y
reconexión. `QModeCatalog`, `QPomodoroConfiguration`, `QPomodoroProgress`, modelos
de perfiles, agentes y reuniones ya están en QCore. La coordinación del producto
sigue mayoritariamente en `QAppModel`; los proveedores actuales usan adaptadores
Mac. No asumir que sus APIs, rutas o permisos existen en Windows/Linux.

## Orden de entrega

| Bloque | Entrega utilizable | Dependencia / criterio para terminar |
| --- | --- | --- |
| 1. Modos + Pomodoro | Selector de modos, foco/descanso, cuenta atrás, controles, progreso LED y recuperación | Misma secuencia de transiciones que Mac; duración, pausa, reposo, reinicio y reconexión probados |
| 2. Relajación + gestos | Gradiente de Mac; ciclo de modos y asignaciones de botón | Los gestos actúan sobre el modo elegido, sin interferencias de otros modos |
| 3. Perfiles personalizados | Editor de tres luces, estados, importación/exportación `.qmode` y acciones compatibles | Intercambio con fixtures de Mac sin pérdida silenciosa; validación y acciones probadas por SO |
| 4. Agentes | Estado local de Codex y Claude Code, prioridades y hasta tres posiciones; acciones donde existan | Cada proveedor tiene evidencia real por SO y distingue observar actividad de abrir/controlar su aplicación |
| 5. Reuniones + disponibilidad automática | Proveedores de reuniones y acciones verificadas de micrófono | Detección y control certificados por proveedor/SO; la disponibilidad manual mantiene prioridad |
| 6. Integración de escritorio y distribución | Inicio opcional con sesión, notificaciones, diagnóstico y actualización de paquetes | Pruebas en equipos sin SDK, recuperación de ajustes y matriz explícita de sistemas soportados |

Cada bloque termina con un paquete para probar, documentación y checks de Mac.
No hace falta esperar a reuniones para entregar Pomodoro o perfiles. No fijar
fechas para proveedores hasta completar su prueba técnica en Windows y Linux.

## Bloque 1: base multimodo y Pomodoro

1. Sustituir la selección fija de disponibilidad por un coordinador pequeño:
   modo seleccionado, estado por modo, escena base y acción contextual. Solo el
   modo seleccionado controla LEDs y botón. El temporizador puede seguir en
   segundo plano sin sustituir la escena de otro modo.
2. Ampliar snapshots/comandos del motor con modos disponibles, capacidades,
   acciones y estado de temporizador. El renderer presenta esos datos; no calcula
   transiciones ni mantiene un segundo temporizador autoritativo. Extender IPC v1
   de forma compatible; cambiar versión si se rompe el contrato y rechazar una
   combinación UI/motor incompatible con un mensaje claro.
3. Introducir ajustes de esquema 2 y migración desde el esquema 1 actual:
   conservar ID del dispositivo, brillo y disponibilidad; añadir modo seleccionado,
   duraciones y estado de la sesión Pomodoro. Guardar copia previa a la migración,
   escribir atómicamente y rechazar versiones futuras sin sobrescribirlas.
4. Caracterizar el comportamiento Mac con pruebas y extraer una máquina de estados
   con reloj inyectable. Reutilizar `QPomodoroProgress` para las tres luces y el
   ajuste de duración que conserva tiempo ya consumido. La adopción por Mac debe
   ser un cambio acotado, separado de la interfaz Electron.
5. Añadir el panel Pomodoro: fase, tiempo restante, duración y acciones contextuales.
   Mantener foco predeterminado de 25 minutos y descanso de 5; los límites actuales
   son 1–180 y 1–60 minutos. No introducir autoarranque de fases ni pausas nuevas
   como efecto secundario del port.
6. Persistir en cambios de configuración/fase/pausa, no cada segundo. Propuesta
   para el cliente portable: una fase activa conserva su vencimiento al reiniciar;
   si venció, mostrar Finished una sola vez y esperar la siguiente acción. Una
   sesión pausada conserva el tiempo restante. Esto añade recuperación portable;
   no cambia automáticamente la persistencia de Mac.

### Comportamiento de referencia y pruebas

El Mac actual inicia foco desde Idle, permite pausar/reanudar foco, y ofrece saltar
el descanso desde su acción contextual. Al vencer una fase pasa a Finished; la
siguiente fase empieza con la acción del usuario. Cambiar de modo no debe dar a
Pomodoro permiso para sobrescribir sus luces. Caracterizar expresamente estos
casos antes de extraer código; no asumir que todas las fases se pueden pausar.

El reloj debe tener una política explícita para suspensión y cambios del reloj
del sistema: recalcular el tiempo transcurrido al reanudar, sin depender del número
de ticks recibidos. Probar foco/descanso completos, pausa, duración editada durante
una sesión, vencimiento durante reposo, cambio de modo, reinicio antes/después del
vencimiento y retirada/reconexión de Q. El USB no es el reloj del temporizador.
Validar migración 1→2, recuperación desde backup y rechazo de ajustes incompatibles.

## Bloque 2: relajación y gestos

Usar directamente el preset `QModeCatalog.relaxing`, con su velocidad y desfases;
evitar una animación distinta calculada por Electron. El botón reinicia el
gradiente según el comportamiento actual. El selector y el ciclo de modos solo
incluyen funciones disponibles. Reutilizar `QGestureSettings` y las reglas
contextuales para pulsación simple/doble/larga; tratar liberación y triple
pulsación explícitamente según las reglas de Mac, sin asignaciones inventadas.
Mostrar confirmación visual de gesto y probar cambios rápidos de modo, brillo y
reconexión durante la animación.

## Bloque 3: perfiles y editor

Reutilizar `QCustomModeDefinition`, escenas y el formato de `custom-mode.schema.json`.
Crear/editar estados, colores, animaciones, intensidades y asignaciones; importar
y exportar `.qmode` mediante diálogos nativos. Validar límites de tamaño, números,
UUID únicos, tres LEDs y referencias a estados antes de aplicar o guardar.

Primero implementar acciones locales (siguiente/anterior estado, apagar, heredar
gesto). Después apertura de URLs y aplicaciones mediante adaptadores de cada SO.
Apple Shortcuts y destinos Mac deben aparecer como no disponibles, conservando
sus datos al volver a exportar. Preservar campos futuros o rechazar el archivo
claramente antes de una edición que los perdería; decodificar y recodificar con
Codable por sí solo no garantiza esa preservación. Importar no ejecuta acciones.
Comprobar intercambio con perfiles reales de Mac y colisiones de identificadores.

## Bloque 4: agentes

Separar lectura/parsing de eventos locales, resolución compartida y acciones del
sistema. Auditar primero los proveedores existentes y los formatos disponibles
en cada equipo. Empezar por el proveedor que pueda demostrar observación fiable;
la preferencia inicial es Codex, seguido de Claude Code, sujeta a esa prueba.

Reutilizar `QAgentSession`, prioridades y presentación de hasta tres tareas.
Probar permisos/input, trabajo, éxito, error, procesos finalizados, eventos
duplicados y datos obsoletos. Verificar por separado que enfocar una tarea abre
la tarea correcta. Si la plataforma solo permite observación, mostrar esa
capacidad sin ofrecer control inexistente. Los hooks de Claude necesitan su
propia instalación/desinstalación reversible, preservando configuración ajena.
El diagnóstico conserva metadatos técnicos y nunca contenido de conversaciones.

## Bloque 5: reuniones y disponibilidad automática

Hacer una prueba técnica por proveedor antes de prometer soporte. Orden inicial:
Discord (su parser está compartido), después Zoom, Meet y Teams según mecanismos
verificables de cada plataforma. No trasladar rutas `Library/...`, AppKit,
Accessibility o AppleScript al cliente portable.

Declarar por proveedor/SO capacidades independientes: detectar llamada, abrir
aplicación, leer mute, cambiar mute y mantener pulsado para hablar. La confirmación
de una acción requiere observar el estado resultante; enviar un atajo no demuestra
éxito. Probar varias reuniones simultáneas, permisos denegados, proveedor cerrado,
mute modificado fuera de Q y liberación tras una interrupción. Disponibilidad
automática se habilita cuando existan fuentes verificadas; la selección manual
y la propiedad del modo siguen siendo explícitas.

## Bloque 6 y relación con actualizaciones Mac

Añadir inicio con sesión como opción, notificaciones y diagnóstico local. Mantener
una ventana accesible en Linux sin bandeja y comprobar los escritorios declarados.
El flasheo de firmware es una subfase independiente: requiere herramienta por SO,
identidad verificada, pausa del transporte y handshake posterior; no es necesario
para integrar estos modos sobre el protocolo USB 1 actual.

Seguir integrando revisiones de Mac en la rama mediante merges normales y comprobar
fuentes compartidas en los tres sistemas. No mantener copias de reglas Swift ni
prometer que una nueva función exclusiva de Mac aparezca automáticamente en el
cliente portable. Un fallo Windows/Linux conserva el último paquete válido y no
bloquea la publicación Mac. Un eventual PR mínimo de extracciones compartidas se
revisa por separado; no cambiar protección de ramas ni activar auto-merge.

## Pendientes transversales y siguiente acción

La prueba física de USB en Linux, suspensión/reanudación y la prueba manual de Mac
siguen pendientes; no confundir tests PTY/Xvfb con esas sesiones. Registrar cada
combinación probada. Repetir checks adecuados a cada extracción y verificar los
paquetes finales que se entregan.

**Siguiente implementación:** bloque 1 en cambios pequeños: primero caracterización
de Pomodoro + coordinador/IPC/migración; después máquina de estados + panel;
finalmente sesión con Q y paquete portable. No empezar proveedores externos antes
de tener estable esta base multimodo.
