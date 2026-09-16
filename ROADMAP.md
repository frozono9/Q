# Q — Roadmap completo del proyecto

Fecha de referencia: **16 de septiembre de 2026**. Base revisada: commit `069ba94`, app y firmware declarados como `0.2.2`, protocolo serie `1`.

Este documento define cómo llevar Q desde el prototipo funcional y la beta privada actuales hasta un producto fiable, fácil de instalar y ampliable. Es un plan de producto e ingeniería, no una promesa de fechas ni una afirmación de que todas las capacidades descritas ya existen.

Complementa a [PROJECT_GUIDE.md](PROJECT_GUIDE.md), que explica el proyecto y su arquitectura, a [README.md](README.md), que cubre uso y compilación, y a [Firmware/README.md](Firmware/README.md), que describe el dispositivo. Cuando una funcionalidad propuesta se implemente, su comportamiento definitivo deberá pasar a esas guías.

## Índice

1. [Visión y criterio de producto](#1-visión-y-criterio-de-producto)
2. [Estado real de partida](#2-estado-real-de-partida)
3. [Decisiones que debemos preservar](#3-decisiones-que-debemos-preservar)
4. [Prioridades y secuencia](#4-prioridades-y-secuencia)
5. [Fase A — Cerrar fiabilidad y Meetings](#5-fase-a--cerrar-fiabilidad-y-meetings)
6. [Fase B — Arquitectura común de agentes](#6-fase-b--arquitectura-común-de-agentes)
7. [Fase C — Claude Code y expansión de agentes](#7-fase-c--claude-code-y-expansión-de-agentes)
8. [Fase D — UX y modos de fábrica](#8-fase-d--ux-y-modos-de-fábrica)
9. [Fase E — Custom, API local, SDK y MCP](#9-fase-e--custom-api-local-sdk-y-mcp)
10. [Fase F — Firmware y hardware de producción](#10-fase-f--firmware-y-hardware-de-producción)
11. [Fase G — Instalación, web y distribución](#11-fase-g--instalación-web-y-distribución)
12. [Fase H — Beta y lanzamiento](#12-fase-h--beta-y-lanzamiento)
13. [Arquitectura y deuda técnica](#13-arquitectura-y-deuda-técnica)
14. [Pruebas y métricas](#14-pruebas-y-métricas)
15. [Privacidad, permisos y confianza](#15-privacidad-permisos-y-confianza)
16. [Backlog priorizado](#16-backlog-priorizado)
17. [Riesgos y decisiones pendientes](#17-riesgos-y-decisiones-pendientes)
18. [Plan operativo inmediato](#18-plan-operativo-inmediato)
19. [Definición de terminado y mantenimiento](#19-definición-de-terminado-y-mantenimiento)
20. [Visión posterior a 1.0](#20-visión-posterior-a-10)

## 1. Visión y criterio de producto

Q es un objeto físico de escritorio que permite entender qué está pasando y actuar sobre ello sin tener que buscar una ventana. Tiene tres LEDs RGB, un botón y una conexión USB-C. La app nativa de macOS traduce actividad del ordenador a estados visibles y asigna al botón una acción contextual.

La experiencia central es: **veo Q, entiendo su estado, pulso Q y ocurre la acción que esperaba**.

El valor del producto depende de que esa relación sea consistente. Un indicador que se equivoca, un botón que abre otra aplicación o una conexión que parpadea en rojo sin motivo dañan más la experiencia que la ausencia de una integración adicional. La expansión debe conservar esa confianza.

### 1.1 Usuarios iniciales

- Personas que usan agentes de programación y quieren saber cuándo necesitan atención.
- Personas que alternan trabajo, llamadas y sesiones de concentración.
- Usuarios que quieren indicar disponibilidad de forma física y discreta.
- Makers y desarrolladores que quieren asignar sus propios estados al dispositivo.

La primera beta se orienta a usuarios de macOS con una PCB Q ya montada. Un colaborador puede querer compilar o extender el proyecto; un usuario normal debe poder instalar la app y conectar el módulo sin herramientas de desarrollo.

### 1.2 Qué significa que Q sea un buen producto

1. Se reconoce y conecta sin seleccionar puertos.
2. El icono de la barra de menús siempre ofrece una entrada a la app mientras esta está ejecutándose.
3. El modo elegido se respeta.
4. Los estados procedentes de integraciones reflejan evidencia real.
5. Las acciones van al objetivo correcto.
6. Las animaciones son agradables y estables.
7. Los errores tienen una explicación y una recuperación sencilla.
8. Otra persona puede instalarlo, usarlo y actualizarlo sin que el creador esté presente.

### 1.3 Qué no es necesario para llegar a 1.0

Una cuenta Q, un servicio cloud, una tienda de plugins, una batería, conexión inalámbrica y una app móvil no son requisitos iniciales. Podrían tener sentido después, pero multiplican mantenimiento y soporte. La primera versión sólida debe demostrar el valor de tres luces y un botón conectados por USB.

## 2. Estado real de partida

Conviene separar cuatro niveles de evidencia:

| Nivel | Significado |
| --- | --- |
| Implementado | Existe código para realizar la función. |
| Verificado automáticamente | Se han ejecutado pruebas que comprueban su comportamiento. Compilar o hacer typecheck no equivale a ejecutar tests. |
| Verificado en uso real | Se ha probado el flujo completo con la app o el hardware correspondiente. |
| Listo para distribución | Se ha repetido en otros equipos y está documentado con sus límites. |

### 2.1 Inventario actual

| Área | Qué existe | Qué queda por cerrar |
| --- | --- | --- |
| Hardware | PCB con XIAO ESP32-C3, tres LEDs RGB y botón; unidades montadas y usadas por el usuario | Repetibilidad entre unidades, pruebas de ensamblaje y tolerancias del housing |
| USB | Descubrimiento, handshake, identidad estable, versión y reconexión | Matriz de hubs, cables, reposo y fallos prolongados |
| Firmware | PWM temporizado, animaciones, gestos y vigilancia de conexión | Medición de estabilidad, pruebas de estrés y recuperación reproducible |
| App | Barra de menús, icono, popover, ajustes, arranque y watcher USB | Uso prolongado, preferencias de arranque y comportamiento al cerrar voluntariamente |
| AI Agents | Integración local de Codex, estados y hasta tres slots | Generalización de proveedores y regresiones de concurrencia |
| Meetings | Adaptadores Discord, Zoom, Meet y Teams; selector Auto/manual y acciones de mute/PTT | Validación real por proveedor y confirmación del estado del micrófono |
| Availability | Estados manuales | Pulido y personalización; la automatización no está terminada |
| Pomodoro | Temporizador configurable, pausa, descanso y progresión de LEDs | Casos de reposo/reinicio y consistencia perceptual entre unidades |
| Relaxing | Gradiente lento | Preferencias sencillas y prueba prolongada a bajo brillo |
| Custom | Editor, estados, acciones e importación/exportación `.qmode` | Versionado, validación completa, API local, SDK y MCP |
| Soporte | Setup, pruebas de LEDs/botón, nombre del dispositivo y diagnóstico | Diagnóstico más preciso de integraciones y guía para testers |
| Actualización | Payload de firmware y herramienta incluidos; reconexión y verificación | Recuperación real tras fallos y prueba en Mac ajeno |
| Distribución | Scripts de bundle y DMG, firma cuando existe identidad | Artefactos reproducibles, compatibilidad publicada y decisión de notarización |

### 2.2 Corrección del nivel de confianza de la última entrega

La última entrega compiló la app universal y el firmware, validó la firma del bundle y permitió observar el selector de Meetings y el Q conectado. Las fuentes de tests se sometieron a typecheck debido al problema local del toolchain SwiftPM.

Eso **no acredita una ejecución completa de la suite ni una prueba de llamadas reales en los cuatro proveedores**. El informe anterior fue demasiado concluyente al describir Meetings como terminado. Este roadmap mantiene la validación de extremo a extremo como trabajo pendiente.

### 2.3 Riesgos concretos visibles en el código

**Actualización de implementación:** el bloque de fiabilidad posterior a la
redacción inicial ya introduce resultados `confirmado/enviado sin confirmar/
fallido`, lectura posterior de controles, activación de la ventana identificada,
vocabulario compartido, cola serial para hold/release, detección específica de
Meet y posiciones de agentes estables. La validación con llamadas reales por
proveedor sigue siendo necesaria antes de cerrar la fase A.

- Las acciones de mute programan trabajo asíncrono y pueden devolver éxito antes de observar el resultado en la aplicación externa.
- El fallback por atajo de teclado depende de que el foco y la ventana adecuados sigan activos al entregar la acción.
- Discord detecta conexión de llamada por logs, pero no observa todos los cambios manuales de mute. `setMuted` consulta un snapshot que puede no representar el estado real del micrófono.
- Teams conserva estados optimistas y utiliza heurísticas de ventana cuando Accessibility no expone controles. Una ventana presente no prueba que el micrófono esté en el estado esperado.
- Google Meet se busca a través de navegadores. Detectar que un navegador está abierto no significa que Meet esté disponible; activar el navegador tampoco garantiza enfocar la pestaña exacta.
- La búsqueda de controles de micrófono y el clasificador no comparten exactamente las mismas reglas de texto. Hay que evitar discrepancias de idioma, acentos y nombres de botón.
- El hold y su release lanzan acciones asíncronas. Deben serializarse para impedir que una orden tardía de desmute llegue después de la de mute.
- El resolver de agentes ordena por prioridad y recencia: todavía hay que definir si preservar posiciones de LEDs durante cambios evita saltos confusos.

Estos puntos son objetivos de investigación y corrección; no implican que todas las rutas fallen siempre.

## 3. Decisiones que debemos preservar

### 3.1 El usuario elige el modo

El modo seleccionado es dueño de LEDs y botón. Una reunión no reemplaza AI Agents. Un agente que pide permiso no reemplaza Pomodoro. Las integraciones pueden observarse en segundo plano, pero actualizan su propio dominio.

Dentro de un modo sí puede existir prioridad: un agente que necesita ayuda merece atención antes que uno trabajando. Eso no autoriza cambios entre modos.

### 3.2 Gramática visual

| Color | Significado de fábrica |
| --- | --- |
| Verde | Disponible, preparado o terminado correctamente |
| Ámbar/amarillo | Trabajo, transición o ausencia |
| Azul | Atención, participación o foco |
| Rojo | Error, bloqueo, no molestar o espera de conexión según contexto |
| Morado | Concentración temporizada |
| Apagado | Sin luz emitida |

| Animación | Uso principal |
| --- | --- |
| Sólido | Estado estable |
| Chase | Actividad continua de un único proceso |
| Fade/pulse | Atención o trabajo individual dentro de varios slots |
| Blink | Problema |
| Flash | Evento que acaba de suceder |
| Depleción progresiva | Tiempo restante |

Los colores son presets editables a futuro. Las alternativas de accesibilidad deben conservar diferencias de movimiento y explicaciones textuales para no depender exclusivamente del color.

### 3.3 Gestos

- Single press: acción contextual del modo.
- Double press: siguiente modo incluido en el ciclo.
- Long press: acción mantenida cuando el modo dispone de ella.
- Release: finaliza la acción iniciada por ese mismo hold, aunque cambie el contexto mientras tanto.

AI Agents conserva el dictado de Codex donde esté disponible. Meetings usa push-to-talk. Para proveedores sin una capacidad equivalente, Q debe mostrar una limitación clara en lugar de enviar una acción a otra app.

### 3.4 Local y extensible

La app decide el significado; el firmware representa luces y comunica gestos. Los nuevos modos e integraciones deberían requerir principalmente cambios de software en el Mac. Se conserva la PCB actual como plataforma de trabajo y no se plantea una revisión sin evidencia de una limitación física.

### 3.5 Decisiones descartadas

El selector de modelo y effort se retiró por petición explícita. No vuelve a formar parte del roadmap. Tampoco se propone restaurar el preview permanente del dispositivo ni ampliar la UI principal con paneles innecesarios.

## 4. Prioridades y secuencia

| Prioridad | Criterio |
| --- | --- |
| P0 | Acción sobre el objetivo equivocado, micrófono sin control fiable, pérdida de conexión o bloqueo del flujo principal |
| P1 | Necesario para beta ampliada o para añadir proveedores sin regresiones |
| P2 | Mejora importante de experiencia o extensión después de estabilizar la base |
| P3 | Experimento o ampliación dependiente de demanda |

Secuencia recomendada: **A → B → C → beta ampliada**, manteniendo pruebas de firmware y UX durante todo el recorrido. D, F y G avanzan por entregables concretos. E empieza por el contrato local después de demostrar un segundo proveedor; la publicación de un SDK requiere estabilidad de ese contrato. H utiliza resultados de todas las anteriores.

| Hito | Resultado visible | Condición de salida |
| --- | --- | --- |
| A. Base fiable | Meetings y botón predecibles | Pruebas reales por proveedor y sin mezcla de modos |
| B. Agentes comunes | Codex funciona sobre la nueva base | Paridad comprobada con el comportamiento actual |
| C. Segundo proveedor | Codex y Claude Code simultáneos | Estados y apertura correctos sin sesiones fantasma |
| D. UX consistente | Menos dudas al configurar o interpretar Q | Flujos de nuevos usuarios completados |
| E. Plataforma local | Un tercero crea una integración o un modo | Ejemplo externo reproducible y contrato versionado |
| F. Hardware repetible | Varias unidades se comportan igual | Prueba por unidad y recuperación documentada |
| G. Distribución | Descargar, instalar y actualizar | Flujo completo en otro Mac |
| H. 1.0 | Producto mantenible con soporte explícito | Criterios de lanzamiento cumplidos |

No se asignan fechas rígidas antes de validar la parte de Meetings y estudiar Claude Code. La dificultad de una integración depende de las señales y controles que realmente exponga su versión instalada.

## 5. Fase A — Cerrar fiabilidad y Meetings

**Prioridad: P0.** Resultado: elegir Meetings y pulsar Q produce una acción comprobable sobre una llamada concreta.

### A1. Separar detección, control y confirmación

Cada adaptador debe informar por separado de aplicación disponible, llamada identificada, estado de micrófono conocido, capacidad de control y resultado de la última acción. No basta con un único booleano de éxito.

Definir resultados como `confirmado`, `enviado sin confirmar`, `no disponible` y `fallido`. La UI puede traducirlos a lenguaje sencillo. El firmware no necesita conocer esta complejidad; la app decide qué estado puede representar honestamente.

La confirmación debe proceder de una lectura posterior o de un mecanismo con garantías conocidas. Si únicamente enviamos un toggle y no observamos su resultado, no debemos presentar un mute confirmado.

### A2. Push-to-talk como ciclo controlado

El ciclo propuesto es: capturar proveedor y llamada → comprobar capacidad → desmutear → mantener → recibir release → mutear el mismo objetivo → confirmar.

Trabajo necesario:

- Mantener identidad de la operación y del objetivo desde el inicio hasta el final.
- Ordenar comandos por proveedor para que release nunca sea adelantado por una acción vieja.
- Hacer idempotentes las solicitudes cuando sea posible.
- Resolver doble recepción de `long`, release repetido y release sin inicio.
- Interrumpir o finalizar el hold al perder el dispositivo, cerrar Q o perder la llamada.
- Establecer un comportamiento explícito al suspender el Mac o cambiar de modo.
- Evitar robar el foco más de lo necesario.
- Mostrar un fallo comprensible si no se puede confirmar el mute final.

El comportamiento de producto solicitado es volver a mute al soltar, incluso si la llamada empezó desmuteada. Debe estar explicado para que el usuario sepa qué esperar.

### A3. Discord

Mantener el parser RTC para presencia de llamada. Investigar una fuente local adecuada para el estado real de mute y reconciliar acciones enviadas por Q con cambios hechos en Discord.

Reproducir específicamente: entrar ya muteado, cambiar mute desde Discord, mantener Q, soltar, repetir. Revisar el uso de `lastSnapshot` en `setMuted`: el snapshot de conexión no es una prueba suficiente del estado del micrófono.

**Aceptación:** llamada y mute no divergen tras cambios manuales ni tras varios holds. Si no hay fuente fiable, publicar esa limitación y no llamar confirmado a un estado supuesto.

### A4. Zoom

Validar ventana normal, controles ocultos, minimización, llamada con otra app delante y distintos textos accesibles. Priorizar la acción sobre el control de la llamada identificada, con fallback explícito y comprobado.

**Aceptación:** single press y hold funcionan en llamadas de prueba sin afectar otras ventanas; salir de la llamada devuelve Free; abrir Zoom sin llamada no genera azul.

### A5. Google Meet

Identificar pestaña y navegador concretos. Limitar lectura y acciones a esa superficie. Evitar que un control de micrófono de otra web se clasifique como Meet.

Validar una pestaña visible, otra en segundo plano y varias ventanas. Si Accessibility no permite garantizar el objetivo, evaluar una extensión de navegador o un puente específico. No prometer soporte para todos los navegadores con el mismo nivel de calidad antes de comprobarlos.

**Aceptación:** pulsar Q actúa sobre la llamada Meet seleccionada, no sobre otra pestaña ni sobre un atajo general del navegador. Diferenciar en Settings «navegador disponible» de «llamada detectada».

### A6. Microsoft Teams

Tratar títulos y niveles de ventana como señales auxiliares. No deducir mute confirmado de la ventana compacta ni del envío de un atajo. Comprobar la app y sus procesos auxiliares con límites de tiempo para que una superficie AX lenta no degrade Q.

Probar ventana principal, compacta, fondo y cambios manuales del micrófono. Guardar la versión de Teams y macOS junto al resultado de prueba, sin contenido de la reunión.

**Aceptación:** comportamiento reproducible en una llamada real, incluida la vuelta a mute al soltar. Si no se consigue confirmación estable, etiquetar el alcance como limitado y definir una alternativa concreta antes de declararlo soportado plenamente.

### A7. Auto y selección manual

El selector existe. Falta cubrir dos llamadas simultáneas, cierre del proveedor fijado, cambio durante un hold y reinicio. Auto necesita una regla estable, explicada y comprobada; la selección manual nunca debe enviar la acción a otro proveedor como fallback silencioso.

También hay que revisar el fallback actual que elige una app por estar al frente o ser la única abierta: eso puede orientar una acción de apertura, pero no demuestra que exista una llamada apta para controlar el micrófono.

### A8. Matriz de aceptación

Para cada proveedor: app cerrada; abierta sin llamada; llamada muteada; llamada desmuteada; cambios manuales; single press; hold/release; otra app al frente; llamada finalizada durante hold; Q desconectado durante hold; reinicio de Q.

Añadir pruebas cruzadas: AI Agents durante llamada conserva LEDs y dictado; Pomodoro durante llamada conserva temporizador; cambiar proveedor durante hold no cambia el destinatario de release.

**Salida de fase:** resultados registrados por proveedor y versión. Un fallo no se convierte en «pasado» porque la app haya compilado.

## 6. Fase B — Arquitectura común de agentes

**Prioridad: P1.** Resultado: Codex es un proveedor dentro de un sistema extensible, con paridad de comportamiento antes de añadir otro.

### B1. Contrato de proveedor

Definir una interfaz con inicio/parada de observación, disponibilidad, emisión de eventos, apertura del objetivo y capacidades opcionales. Separar el detector de la acción de enfocar y del dictado.

El contrato debe permitir proveedores de archivos locales, hooks, un puente o una integración explícita sin obligarlos a simular ventanas o atajos que no poseen.

### B2. Identidad de sesión y turno

El modelo actual ya tiene `id`, `source`, `displayName`, `state`, contexto y fecha. Evolucionarlo con identidad compuesta de proveedor y sesión, identidad de ejecución/turno cuando exista, hora de actividad real, fuente de evidencia y referencia tipada al objetivo.

No confundir conversación abierta con agente trabajando. Una conversación puede tener muchos turnos; una sesión puede quedar abierta sin actividad; una tarea puede finalizar y arrancar otra. La idempotencia y el descarte de eventos antiguos deben basarse en esa identidad.

### B3. Estados normalizados

| Estado semántico | Evidencia esperada | Representación habitual |
| --- | --- | --- |
| Idle | Sin ejecución relevante | Chase verde |
| Working | Turno activo con señal vigente | Chase ámbar si está solo |
| Needs you | Solicitud explícita de permiso o entrada | Azul pulsante |
| Done | Finalización explícita | Verde durante la ventana de finalización |
| Error | Fallo explícito | Rojo |
| Desconocido/desconectado | La fuente dejó de ser observable | Estado de integración en UI; política de caducidad |

No inferir Done solo porque no hay actividad durante unos segundos. No inferir Needs you porque exista una ventana. Diferenciar cancelar de fallar y documentar cómo se representa una cancelación.

### B4. Agregador y vida útil

- Consumir todos los proveedores habilitados.
- Deduplicar eventos y sesiones.
- Ignorar datos fuera de orden cuando ya existe un estado más reciente.
- Expirar estados transitorios sin borrar sesiones activas legítimas.
- Limpiar sesiones del proveedor desconectado con una política visible.
- Conservar la ventana breve de finalización que permite ver un slot verde antes de volver a un único agente.
- Mantener la prioridad semántica dentro de AI Agents.

Las duraciones actuales de finalización/error son referencia de partida, no razón para copiar supuestos a todos los proveedores. Deben probarse con relojes controlables.

### B5. Tres LEDs, muchos agentes

La semántica acordada se mantiene: uno trabajando usa los tres LEDs en chase; dos o tres relevantes usan un slot cada uno; un agente terminado aparece brevemente en verde y después deja libre su slot; si queda uno, vuelve el chase completo.

Con más de tres agentes, mostrar los más relevantes y el total en la app. Evitar rotación automática confusa de LEDs. Evaluar conservar slots mientras siguen activos para que la posición tenga continuidad, definiendo cuándo un Needs you puede desplazar a otro.

Casos obligatorios: dos empiezan juntos; uno termina; ambos terminan; empieza un tercero después; llega un evento de finalización antiguo; un proveedor se cierra; dos proveedores usan el mismo identificador nativo; cuatro tareas compiten por tres slots.

### B6. Acciones correctas

Pulsar Q debe abrir el objetivo del agente seleccionado por el resolver. Un proveedor sin enlace a sesión exacta puede ofrecer abrir la app, pero esa capacidad debe declararse como aproximada.

El dictado pertenece a la capacidad de un proveedor. Añadir Claude Code no debe provocar que mantener Q abra Codex aunque la tarea relevante sea de Claude. La política para fuentes sin dictado deberá definirse y mostrarse antes de habilitarlas en Auto.

### B7. Selector de fuentes

Añadir Auto/todas las habilitadas y filtros por proveedor realmente instalado. Mostrar disponibilidad, última señal y capacidades en detalles de integración. Evitar opciones de proveedores todavía no implementados como si estuvieran funcionando.

**Salida de fase:** todos los escenarios actuales de Codex pasan con el nuevo contrato; no cambia la semántica de sus LEDs ni la precisión de la apertura.

## 7. Fase C — Claude Code y expansión de agentes

**Prioridad: P1 para Claude Code; P2 para las siguientes fuentes.** Las vías de integración de productos externos deben verificarse en su documentación y versión instalada al empezar cada adaptador. Aquí no se presuponen APIs, hooks ni enlaces que aún no se han investigado.

### C1. Descubrimiento de Claude Code

Estudiar señales disponibles para inicio de turno, uso de herramientas, solicitud de permiso, espera de usuario, finalización, error y cierre de sesión. Comparar hooks documentados, registros locales y otras interfaces disponibles.

La elección debe priorizar eventos explícitos, estabilidad y capacidad de identificar la sesión. Documentar permisos, configuración necesaria, coste de mantenimiento y límites de apertura. Claude Code y la app de escritorio Claude son superficies distintas; soportar una no acredita la otra.

### C2. Instalación comprensible

Proporcionar un flujo que compruebe si Claude Code está instalado, explique qué debe conectarse a Q y ofrezca una prueba. Cualquier cambio en configuración existente debe combinarse de forma conservadora, ser reversible y preservar los hooks del usuario.

No sobrescribir archivos enteros para añadir una entrada. Ofrecer desconexión que retire solo lo añadido por Q. Si requiere intervención en terminal, dar instrucciones breves y verificables.

### C3. Primera versión del adaptador

Entregar Working, Needs you, Done y Error; múltiples sesiones; limpieza al cerrar; identificación visible del proveedor; acción de apertura con alcance explícito. Separar las capacidades que se pueden garantizar de las pendientes.

Probar una tarea sencilla, una solicitud real de permiso, rechazo de permiso, cancelación, fallo y dos sesiones paralelas. Después mezclar una sesión Claude Code con una Codex.

**Aceptación:** ambos proveedores comparten LEDs correctamente y una solicitud de Claude nunca enfoca una tarea de Codex por accidente.

### C4. ChatGPT y Claude de escritorio

Hacer una exploración acotada antes de prometer soporte. Preguntas: ¿hay eventos locales explícitos?, ¿se distingue generar de esperar entrada?, ¿se identifica una conversación?, ¿se puede abrir el destino exacto?, ¿qué permisos requiere?

Si solo existe observación de UI, evaluar sensibilidad a idioma, rediseños y ventanas ocultas. No presentar detección de «app abierta» como detección de agente trabajando. Si el resultado no es fiable, ofrecer una integración voluntaria mediante puente o dejarla experimental.

### C5. Otros agentes

Priorizar herramientas realmente usadas por los testers: CLI, IDE y agentes creados por ellos. Evaluar cada candidata por demanda, señales explícitas, precisión de apertura y mantenimiento. El puente local de la fase E debería permitir cubrir casos propios sin un adaptador específico en cada release de Q.

### C6. Calidad publicada por capacidad

Una tabla de compatibilidad futura debe separar detección, Needs you, sesiones simultáneas, apertura exacta y dictado. Un check global por aplicación oculta diferencias importantes. Registrar versiones probadas y fecha de última validación.

## 8. Fase D — UX y modos de fábrica

**Prioridad: P1 para errores y claridad; P2 para personalización.** Mantener un popover pequeño y una jerarquía sencilla: modo, estado, acción principal y acceso a configuración.

### D1. Barra de menús y ventanas

- Comprobar icono en temas claro/oscuro, diferentes escalados y pantallas.
- Evitar duplicar el logo con otra Q decorativa.
- Probar ajustes desde la primera apertura y tras volver al contenido principal.
- Hacer que el tamaño del popover siga el contenido sin conservar espacio vacío.
- Asegurar interacción por teclado, VoiceOver y foco predecible.
- Revisar textos largos de proveedor y nombres personalizados.

La visibilidad del icono también puede verse afectada por la configuración de la barra del usuario; Q debe conservar su elemento y no desaparecer por errores propios.

### D2. Conexión y diagnóstico

Mostrar dispositivo conectado, nombre y un estado resumido. Los detalles técnicos —puerto, versión e identificador— pertenecen a Settings/Support. Diferenciar falta de hardware, firmware incompatible, app externa cerrada, permiso faltante y señal no confirmada.

Añadir una prueba de integración que no necesite interpretar logs. Por ejemplo: «Abre una llamada de prueba», «Q detecta llamada», «Prueba mute», «Mantén y suelta». El paso solo se marca confirmado cuando exista evidencia o confirmación humana registrada.

### D3. Availability

Conservar el ciclo Available → Focus → Busy → Available. Away y Offline siguen siendo opciones explícitas. Permitir elegir estados del ciclo si aparece demanda real, sin convertir la configuración básica en un editor complejo.

La detección automática de ausencia o integración con Focus de macOS se estudia después. Debe ser optativa y actuar solo dentro del modo, con una regla para respetar cambios manuales. No sincronizar con aplicaciones de trabajo sin un contrato definido.

### D4. Pomodoro

Preservar foco morado estable y descanso verde con depleción progresiva. Ajustar duración debe conservar el tiempo transcurrido según una regla documentada. Definir qué ocurre si la nueva duración es menor que el tiempo ya consumido.

Validar pausa, reanudación, cambio de fase, fin y skip; reposo del Mac; cambio de hora; reinicio; desconexión del Q. Decidir explícitamente si el reposo cuenta como tiempo de sesión y mostrarlo en preferencias solo si merece una opción.

Mejoras posibles: presets personales, descanso largo tras varios ciclos, sonido opcional y persistencia de sesión. Las estadísticas extensas quedan para después de confirmar demanda.

### D5. Relaxing

Mantener gradientes lentos sin saltos ni flicker perceptible. Ofrecer velocidad y, más adelante, unas pocas paletas. Probar bajo brillo, cambios de modo y reconexión sin destellos. Un temporizador de apagado podría ser útil, pero no necesita bloquear el lanzamiento.

### D6. Gestos y notificaciones

Mostrar el resultado de single/double y acciones relevantes durante cinco segundos, preservando la excepción de dictado para no interferir. Las acciones mantenidas deberían ofrecer una indicación que refleje duración/fin y no una notificación genérica del modo.

Revisar qué ocurre al cambiar asignaciones mientras hay un hold, personalizar un modo, o recibir eventos repetidos. Dar una opción clara para restaurar mappings de fábrica.

### D7. Personalización accesible

Permitir editar presets de fábrica después de estabilizar la base: colores, brillo y ciertos movimientos. Incluir restauración por estado y por modo. Separar brillo global de brillo de una escena para que editar uno no destruya el otro.

Evaluar paletas para dificultades de percepción del color y una opción de movimiento reducido. La app siempre debe describir en texto el estado que muestran los LEDs.

## 9. Fase E — Custom, API local, SDK y MCP

**Prioridad: P2.** Resultado: los amigos que reciben una PCB pueden crear comportamientos propios sin modificar firmware ni comprender toda la app.

### E1. Consolidar el editor existente

Validar nombres, colores, rangos, estados iniciales e identificadores. Añadir duplicar/reordenar estados, deshacer donde resulte útil, avisos de cambios sin guardar y restauración sencilla.

La importación debe detectar archivos incompletos, versiones futuras y referencias inválidas. Un `.qmode` debe poder exportarse, importarse en otro Mac y conservar su intención sin depender de rutas personales que no existen allí.

Distinguir acciones portables de las que dependen de una app o Shortcut local. Informar qué falta después de importar, sin ejecutar automáticamente acciones del archivo.

### E2. Contrato versionado

Evolucionar [custom-mode.schema.json](Docs/custom-mode.schema.json) con versión de formato y política de migración. Cubrir tamaños máximos, número razonable de estados, rangos de animación y comportamiento de campos desconocidos.

No exponer directamente el transporte serie como API pública. Los clientes proponen estados y acciones al modelo de la app; esta conserva el control del modo activo y la conexión física.

### E3. Canal local común

Diseñar IPC local autenticado o restringido al usuario del Mac. Elegir transporte tras evaluar distribución y clientes previstos. No es necesario abrir un puerto de red accesible desde otros equipos.

Operaciones candidatas: listar capacidades, registrar una fuente, publicar estado, finalizar/retirar estado, listar modos propios y recibir eventos de botón permitidos. Definir propiedad por cliente, duración/expiración, reconexión, límites y limpieza tras crash.

Una fuente externa actualiza su propio modo o participa en AI Agents mediante un contrato explícito. No debe poder cambiar el modo seleccionado silenciosamente.

### E4. CLI y SDK

Empezar con una CLI pequeña y un ejemplo completo. Después elegir el primer SDK según los colaboradores; Python o TypeScript son candidatos, no dos compromisos obligatorios desde el principio.

Ejemplo de experiencia deseada: conectar cliente, declarar tarea, publicar Working, pedir atención, recibir botón, finalizar. Incluir un simulador para desarrollar sin PCB y tests del contrato contra la app.

**Aceptación:** un colaborador distinto al autor consigue crear una integración siguiendo únicamente la documentación.

### E5. MCP

Implementarlo sobre el mismo contrato local, evitando lógica duplicada. Herramientas candidatas: consultar Q, crear borrador de modo, validar configuración, instalar modo y publicar estado de una fuente autorizada.

Definir cuándo una herramienta solo propone y cuándo modifica. Un perfil importado o generado no debe convertirse en ejecución de comandos arbitrarios. Las acciones disponibles deberían conservar el alcance limitado del editor o ampliar ese alcance de forma explícita y revisable.

### E6. Crear un modo con IA

Flujo propuesto: describir intención → generar un `.qmode` válido → mostrar estados y acciones → probar en el dispositivo → guardar. La IA puede ejecutarse en la herramienta que el usuario ya emplea; no hace falta integrar un proveedor de modelos de pago dentro de Q para la primera versión.

Si una petición necesita datos externos, indicar el conector o fuente necesaria. Generar colores y nombres no constituye una integración real con un calendario, una build o un servicio.

### E7. Ejemplos iniciales

- Resultado de un script: trabajando, terminado, error.
- Sesión de estudio con fases propias.
- Temporizador sencillo de cocina/escritorio.
- Build local con resultado y apertura del log.
- Acción de Apple Shortcuts con estado explícito.

Cada ejemplo debe incluir configuración, ejecución, cierre y comportamiento si el productor desaparece. Un catálogo remoto público y moderado puede esperar.

## 10. Fase F — Firmware y hardware de producción

**Prioridad: P1 para estabilidad y recuperación; P2 para calibración avanzada.** No hay motivo demostrado en este roadmap para pedir otra PCB.

### F1. Estabilidad de luz

El firmware actual utiliza PWM por timer de aproximadamente 391 Hz para nueve canales y una corrección RGB inicial. Medir estabilidad con escenas sólidas, gradientes y tráfico USB intenso. Distinguir parpadeo visible a simple vista de bandas captadas por una cámara.

Comprobar mínimos de brillo y pasos perceptuales, especialmente el final de la depleción Pomodoro. Una curva numéricamente lineal no garantiza una caída visual uniforme. Registrar ajustes por canal y probar que no perjudican el resto de colores.

### F2. Conexión y heartbeat

Preservar la política que tolera retrasos antes de volver al rojo de espera. Probar Mac ocupado, reposo/despertar, cierre de Q, cable retirado, hub desconectado, puerto temporalmente ocupado y app reiniciada.

Las tres pulsaciones verdes deben indicar un handshake nuevo real. Un heartbeat tardío no debe producir repetidas celebraciones de conexión. Registrar contadores locales de reconexión para diagnosticar sin depender de observar el dispositivo durante horas.

### F3. Protocolo

Documentar límites de longitud, líneas parciales, valores inválidos y versiones incompatibles. Ignorar entradas malformadas sin corromper escenas ni bloquear el loop. Revisar uso de memoria y comportamiento tras muchas horas.

Si se amplía el protocolo, negociar capacidades manteniendo compatibilidad o explicando la actualización necesaria. No cambiar el significado de comandos existentes sin aumentar la versión adecuada.

### F4. Firmware updater

Probar una unidad con firmware antiguo y otra actualizada; retirada de USB; error de herramienta; puerto ocupado; reinicio de la app; payload corrupto y reconexión con versión inesperada. No declarar éxito hasta el handshake posterior.

Documentar recuperación por bootloader cuando el firmware no puede responder. El updater normal verifica el dispositivo por handshake; una ruta de recuperación sin handshake necesita identificación y elección explícitas para no flashear otra placa.

Mantener manifiesto de payload, versión, digest y herramienta incluida. Las verificaciones de build y las de ejecución tienen objetivos distintos y ambas deben quedar claras.

### F5. Prueba por unidad

Preparar un procedimiento breve: inspección visual, arranque, handshake, identificación, RGBW en cada LED, brillo bajo/alto, single/double/hold/release y montaje en housing. Registrar aprobado/fallo por identificador y versión de firmware.

Para los módulos de amigos, adjuntar una ficha mínima: unidad, firmware, fecha y enlace a instrucciones. Esto permite distinguir un fallo de software de una soldadura, cable o pulsador.

### F6. Mecánica y producción

Comprobar acceso USB-C, movimiento del botón, luz entre ventanas, tolerancias del housing y esfuerzos del cable. Revisar repetibilidad de soldadura y montaje antes de aumentar unidades.

Si se plantea vender, abrir una revisión específica de requisitos eléctricos, materiales, etiquetado y normativa aplicable al mercado elegido. No afirmar certificaciones ni tomar este roadmap como evaluación de cumplimiento.

### F7. Varios dispositivos

Actualmente se controla uno. Investigar después una selección explícita de dispositivo y preferencias por identidad: mismo modo en ambos, modos distintos o uno dedicado a una fuente. Antes de construirlo, confirmar que los usuarios necesitan varios Q en el mismo Mac.

## 11. Fase G — Instalación, web y distribución

**Prioridad: P1 para beta compartida.** Descargar Q debe conducir a un dispositivo funcionando sin compilar software.

### G1. Un artefacto identificable

Generar app universal y DMG con nombre/versionado coherentes. El DMG conserva el diseño solicitado: Q y acceso a Applications, sin ilustración adicional. Verificar que el binario, el firmware embebido, las notas de versión y el nombre del archivo corresponden a la misma entrega.

Separar canal de desarrollo y beta distribuida cuando sea necesario para evitar que una compilación local se presente como una release ya probada.

### G2. Firma y notarización

El proyecto tiene scripts y la última instalación validó firma. Eso no demuestra que un DMG publicado esté notarizado. Documentar el estado real de cada artefacto.

Mantener la distribución privada sin notarización como opción si se acepta la fricción de primer arranque. La decisión de contratar o mantener servicios de firma/notarización corresponde al propietario. Si se prepara lanzamiento público, revisar entonces requisitos actuales y coste con fuentes oficiales; no asumirlos a partir de recuerdos de la conversación.

### G3. Primer arranque

Validar copiar a Applications, abrir desde Finder/Spotlight, permisos, conexión y primera señal. Diferenciar requisitos para ejecutar la app de requisitos para compilarla: un usuario final no necesita Swift ni Xcode.

El setup debe explicar cada permiso justo cuando hace falta. Poder saltar integraciones opcionales. Al conectar un Q, informar sin convertir cada reconexión en una interrupción molesta.

### G4. Arranque automático y salida

Exponer preferencias comprensibles para abrir al iniciar sesión y abrir al conectar un módulo. Definir qué significa Quit: Q debe poder cerrarse voluntariamente sin una lucha continua con el watcher.

Documentar cómo desactivar o retirar el helper. Probar app movida, eliminada o actualizada, y evitar instancias duplicadas. La detección USB genérica actual debe considerarse una pista para lanzar la app; el handshake sigue determinando si el dispositivo es Q.

### G5. Web mínima

Construir cuando exista un artefacto listo para compartir. Contenido: qué es Q, foto/vídeo real, modos, plataformas compatibles, descarga, instalación, privacidad, soporte y enlace para contribuidores.

Publicar versión, fecha, requisitos de macOS, firmware y notas de cambios. El botón de descarga debe señalar a un artefacto estable y verificable. No presentar como soportadas integraciones que siguen experimentales.

La primera web no necesita cuenta, tienda ni backend de usuarios. Hosting y ubicación de descargas se eligen cuando se ejecute esa tarea.

### G6. Actualizaciones de app

Empezar con comprobar versión y ofrecer descarga si la automatización completa todavía no compensa. Si se incorpora actualizador automático, exigir autenticidad de releases, compatibilidad, conservación de preferencias, cierre limpio de holds y recuperación tras fallo.

No confundir actualización de app con actualización de firmware. La UI debe explicar qué se actualiza y por qué.

### G7. Documentación y licencia

Corregir referencias antiguas de versión y lenguaje que mezcle implementado con validado. Preparar instrucciones de usuario, contribución y diagnóstico separadas. Revisar licencia del proyecto y de recursos/binarios antes de invitar públicamente a redistribuir o comercializar variantes.

No seleccionar una licencia por inercia: documentar qué quiere permitir el propietario respecto a código, hardware y marca.

## 12. Fase H — Beta y lanzamiento

### H1. Beta con amigos

Empezar con las unidades existentes y una versión identificada. Cada tester recibe app, módulo, cable adecuado e instrucciones. Pedir tareas concretas: instalación, conexión, modo habitual, botón y actualización cuando corresponda.

Observar dónde necesita ayuda sin convertir la sesión en una explicación guiada permanente. Registrar problemas por escenario, no solo «funciona/no funciona».

### H2. Registro de incidencias

Plantilla: versión app/firmware, macOS, proveedor y versión, modo, pasos, esperado, observado, frecuencia y diagnóstico opcional. No pedir chats o contenido de llamadas por defecto.

Priorizar acciones equivocadas y pérdidas de estado antes de añadir funciones. Consolidar problemas repetidos y reproducirlos antes de atribuirlos al hardware.

### H3. Candidato de lanzamiento

Congelar nuevas funciones, ejecutar matriz de regresión, publicar notas y repetir instalación en un Mac ajeno. No cambiar firmware, dependencias y todos los adaptadores a la vez durante el cierre.

El número 1.0 debe representar un alcance probado. Es preferible declarar explícitamente una integración experimental que etiquetar todo como estable para completar una lista.

### H4. Criterios de 1.0

- Instalación y primer uso completados por otra persona sin asistencia técnica.
- Conexión/reconexión y uso prolongado sin fallos inexplicados.
- Ninguna acción conocida que se dirija a una app o sesión equivocada.
- Estados de micrófono presentados con el nivel de certeza real.
- Suite automatizada ejecutable y con resultados guardados.
- Compatibilidad por proveedor publicada.
- Actualización de firmware probada y recuperación documentada.
- Documentación, release y artefactos alineados.
- Canal de reporte y responsable de mantenimiento definidos.

La segunda integración de agentes aporta mucho valor, pero una API pública extensa, múltiples dispositivos y plataformas adicionales no necesitan entrar en 1.0.

## 13. Arquitectura y deuda técnica

### 13.1 Responsabilidades propuestas

| Componente | Responsabilidad |
| --- | --- |
| Adaptadores | Observar una fuente y ejecutar acciones sobre objetivos identificados |
| Coordinador de agentes | Unificar sesiones, caducidad y capacidades |
| Coordinador de Meetings | Resolver proveedor, llamada y comandos de micrófono |
| Router de gestos | Interpretar configuración y conservar el ciclo hold/release |
| Estado de modos | Mantener el estado independiente de cada modo |
| Renderizador de escenas | Convertir estado semántico a tres LEDs |
| Transporte | Identidad, serialización, conexión y heartbeat |
| App/UI | Presentar estado y recibir intención del usuario |
| Puente local | Validar clientes y traducir eventos externos al modelo |

### 13.2 Refactor progresivo

`QAppModel` concentra muchas responsabilidades. Extraer componentes al trabajar en el comportamiento correspondiente, manteniendo pruebas alrededor. Evitar una reescritura completa que haga difícil distinguir cambios de arquitectura y regresiones de producto.

Inyectar reloj y dependencias de integración donde permitan reproducir carreras, expiración y fallos. Empezar por los puntos con más riesgo: hold/release, micrófono, agregación de sesiones y reconexión.

### 13.3 Observabilidad

Usar eventos locales estructurados con proveedor, operación, resultado y duración. Evitar volcar árboles de Accessibility, títulos privados o contenido de sesiones. Limitar tamaño y retención.

El diagnóstico debe distinguir «orden enviada» de «estado confirmado» y «navegador abierto» de «Meet detectado». Un botón de copiar informe debe permitir entender qué información se comparte.

### 13.4 Persistencia y migraciones

Versionar preferencias cuando cambie su estructura. Conservar nombres, brillo, modos y mappings tras actualización. Definir backup/importación de configuración si ayuda a mover un Q entre Macs; actualmente las preferencias viven en el Mac, no en la PCB.

### 13.5 Build y CI

Resolver un entorno soportado donde `swift test` se ejecute realmente. El fallback de compilación directa es útil, pero no sustituye al runner de tests. Añadir CI macOS para app/tests y build de firmware, con versiones de herramientas registradas.

Separar secretos de firma del repositorio. Publicar artefactos solo desde un flujo controlado con versión y commit identificables. No regenerar binarios distribuidos sin actualizar su manifiesto.

## 14. Pruebas y métricas

### 14.1 Pirámide de verificación

1. Tests de modelos: escenas, temporizadores, clasificación y arbitraje.
2. Tests de coordinadores: eventos desordenados, caducidad, cancelación y acciones repetidas.
3. Fixtures de adaptadores: datos mínimos anonimizados de distintas versiones/idiomas.
4. Pruebas de UI: navegación, dimensiones, settings y persistencia.
5. Pruebas con hardware: gestos, conexión, brillo, animaciones y actualización.
6. Pruebas externas reales: cada proveedor con una llamada o tarea de prueba.
7. Soak: uso continuado con estados y reconexiones repetidos.

### 14.2 Objetivos iniciales de calidad

Son metas propuestas, no mediciones alcanzadas. Ajustarlas después de obtener una línea base en el Mac actual y otro equipo.

| Métrica | Objetivo inicial | Cómo medir |
| --- | --- | --- |
| Conexión normal | Estado operativo en aproximadamente 5 s | Desde conexión USB a escena aplicada |
| Estado de agente | Reflejar evento explícito en menos de 2 s en condiciones normales | Marca del evento frente a cambio de escena |
| Acción de botón | Entrega rápida y predecible después de reconocer el gesto | Separar umbral de hold de latencia de acción |
| Release PTT | Mute confirmado idealmente en menos de 500 ms | Medir estado observado, no solo envío |
| Destino incorrecto | Cero casos conocidos en matriz de aceptación | Sesiones/proveedores concurrentes |
| Rojo de desconexión espurio | Cero en prueba prolongada sin pérdida real | Registro de conexión más observación |
| CPU en reposo | Bajo consumo, objetivo orientativo medio inferior al 1% | Indicar equipo, duración y adaptadores activos |
| Memoria | Sin crecimiento sostenido | Comparar después de calentamiento y ciclos repetidos |
| Autonomía del usuario | Instalar y ver respuesta en pocos minutos | Prueba sin instrucciones verbales del autor |

### 14.3 Matriz mínima de entorno

Probar Apple silicon y un Intel cuando se disponga de él; versiones de macOS declaradas compatibles; USB directo y hub; permiso Accessibility concedido/retirado; aplicaciones externas actualizadas; textos en inglés y español; pantalla bloqueada y reposo.

Compilar un binario universal no acredita ejecución en Intel. Declarar esa diferencia en resultados de release.

### 14.4 Evidencia

Guardar fecha, commit, firmware, entorno, pasos y resultado. Registrar claramente `pasado`, `fallido`, `no ejecutado` o `bloqueado`. Un vídeo breve puede acompañar las pruebas de luz o botones, pero no sustituye a describir el caso.

## 15. Privacidad, permisos y confianza

Q debe seguir funcionando sin enviar conversaciones, llamadas o actividad a un servidor. Las integraciones necesitan leer señales concretas; documentar cuáles y reducirlas al mínimo útil.

Accessibility es una capacidad amplia. Explicar su uso para observar controles y realizar acciones, y degradar con claridad cuando se retire. No solicitar permisos extra solo para que una heurística parezca más fiable sin estudiar alternativas.

El dictado actual pertenece a Codex. Q no debe presentarse como una app que graba audio si únicamente activa ese control. Si una integración futura captura audio directamente, sería una funcionalidad nueva con decisiones propias de producto y permisos.

Para API/SDK/MCP: aislar fuentes, limitar payloads, establecer expiración y evitar ejecución arbitraria escondida en perfiles. Para diagnósticos: mantener datos locales y compartirlos por acción del usuario, sin telemetría remota obligatoria.

## 16. Backlog priorizado

Los identificadores permiten convertir este documento en issues sin perder contexto. «Base existente» significa que hay implementación parcial o inicial; no que el criterio esté cerrado.

| ID | Prioridad | Trabajo | Dependencia | Cierre |
| --- | --- | --- | --- | --- |
| Q-001 | P0 | Resultado confirmado de acciones de micrófono | Base Meetings | Diferenciar enviado/confirmado/fallido |
| Q-002 | P0 | Serializar hold/release y cancelación | Q-001 | Ninguna orden tardía desmutea tras release |
| Q-003 | P0 | Reconciliar mute de Discord | Q-001 | Cambios manuales y PTT repetido correctos |
| Q-004 | P0 | Validar Teams real | Q-001, Q-002 | Matriz registrada o limitación explícita |
| Q-005 | P0 | Apuntar a pestaña Meet exacta | Investigación navegador | No accionar otra pestaña |
| Q-006 | P0 | Validar Zoom real | Q-001, Q-002 | Matriz registrada |
| Q-007 | P0 | Recuperar hold al desconectar Q | Q-002 | Finalización consistente y estado honesto |
| Q-008 | P1 | Ejecutar suite Swift en entorno soportado | Toolchain | Resultado de tests, no solo typecheck |
| Q-009 | P1 | Contrato de proveedores de agentes | B1 | Codex migrado con paridad |
| Q-010 | P1 | Identidad de turno y caducidad | Q-009 | Eventos antiguos no contaminan tareas nuevas |
| Q-011 | P1 | Resolver mixto y slots | Q-010 | Escenarios uno/dos/tres/más de tres |
| Q-012 | P1 | Acción por capacidad de proveedor | Q-009 | Apertura/dictado siempre coherentes |
| Q-013 | P1 | Investigación Claude Code | B1 | Vía de integración documentada |
| Q-014 | P1 | Adaptador Claude Code | Q-009–Q-013 | Ciclo completo y mezcla con Codex |
| Q-015 | P1 | Selector de fuentes IA | Q-014 | Auto y filtro con disponibilidad real |
| Q-016 | P1 | Tests de reconexión y reposo | Hardware disponible | Sin reconexiones falsas en matriz |
| Q-017 | P1 | Recuperación del updater | Payload actual | Fallos y retry probados |
| Q-018 | P1 | Prueba por unidad | F5 | Registro reproducible por dispositivo |
| Q-019 | P1 | Instalación en Mac ajeno | DMG versionado | Setup completado sin herramientas dev |
| Q-020 | P1 | Semántica Quit/autoarranque | Watcher existente | Usuario puede controlar el lanzamiento |
| Q-021 | P1 | CI de app/tests/firmware | Q-008 | Checks automáticos por cambio |
| Q-022 | P1 | Compatibilidad y notas reales | Resultados de pruebas | Docs alineadas con evidencia |
| Q-023 | P2 | Refinar Pomodoro y reposo | Timer existente | Semántica temporal documentada |
| Q-024 | P2 | Personalizar presets | Configuración versionada | Editar y restaurar sin romper defaults |
| Q-025 | P2 | Custom portable y validado | Editor existente | Roundtrip entre dos Macs |
| Q-026 | P2 | IPC local versionado | Q-009, Q-025 | Fuente externa aislada y caducable |
| Q-027 | P2 | CLI y primer SDK | Q-026 | Ejemplo implementado por colaborador |
| Q-028 | P2 | MCP y generación de modos | Q-025–Q-027 | Borrador revisable y modo funcional |
| Q-029 | P2 | ChatGPT/Claude desktop: viabilidad | B1 | Alcance técnico probado antes de prometer |
| Q-030 | P2 | Web y descarga beta | Q-019, Q-022 | Descarga correcta y documentación accesible |
| Q-031 | P2 | Actualizador de app | Distribución estable | Conserva configuración y valida artefactos |
| Q-032 | P2 | Calibración perceptual y accesibilidad | Medición hardware | Brillo/movimiento consistentes |
| Q-033 | P3 | Varios Q en un Mac | Demanda de usuarios | Identidad y configuración por unidad |
| Q-034 | P3 | Builds como integración utilizable | Q-026 | Caso real; decidir modo o Custom |
| Q-035 | P3 | Otras plataformas | Demanda y capacidad de soporte | Diseño específico, no simple promesa de port |

## 17. Riesgos y decisiones pendientes

| Riesgo | Consecuencia | Mitigación propuesta |
| --- | --- | --- |
| Cambios de UI externa | Detección/control dejan de funcionar | Fixtures, versiones probadas y fallos visibles |
| Mute optimista | LEDs contradicen el micrófono | Confirmar estado y publicar incertidumbre |
| Foco equivocado | Atajo actúa sobre otra superficie | Identificar objetivo y verificar entrega |
| Release perdido | Acción mantenida sigue activa | Ciclo cancelable y recuperación |
| Sesión IA obsoleta | Slots verdes/azules que ya no corresponden | Identidad de turno, caducidad y eventos explícitos |
| Refactor amplio | Regresiones simultáneas | Migración por comportamiento con paridad |
| Más proveedores que capacidad de mantenimiento | Compatibilidad irregular | Priorizar demanda y capacidades observables |
| Variación entre PCBs | Brillo/color diferente | Prueba por unidad y calibración medida |
| Distribución confusa | Tester usa una versión antigua | Artefactos identificados y una descarga principal |
| Documentación demasiado optimista | Expectativas incumplidas | Etiquetar implementado, probado y limitado |

Decisiones que conviene resolver al llegar a su fase:

1. Política de slots: máxima estabilidad espacial frente a reordenación por prioridad.
2. Long press cuando el agente seleccionado no admite dictado.
3. Persistir modo activo y sesión Pomodoro al reiniciar, con comportamiento de recuperación definido.
4. Navegadores de Meet que se soportarán oficialmente primero.
5. Canal de distribución y decisión de notarización.
6. Licencia de código, hardware y uso de marca.
7. Primer lenguaje de SDK según colaboradores reales.
8. Calibración global, por unidad o por lote.

Estas decisiones no bloquean redactar contratos y pruebas; sí deben cerrarse antes de implementar comportamientos visibles ambiguos.

## 18. Plan operativo inmediato

### Entrega 1 — Evidencia y corrección de Meetings

Crear una matriz de pruebas ejecutable, reproducir los fallos de PTT, corregir orden y confirmación de comandos y registrar resultados reales. Revisar Discord antes de asumir que su estado local es fiable; Teams y Meet requieren especial atención al objetivo exacto.

Entregables: correcciones, tests de carreras, informe por proveedor, app instalada y documentación de límites. No ampliar agentes dentro del mismo cambio si sigue existiendo una acción de micrófono incorrecta conocida.

### Entrega 2 — Base multiproveedor

Introducir contratos de sesión, capacidades y eventos; extraer el coordinador; migrar Codex; ejecutar fixtures y casos de concurrencia. La UI visible puede permanecer prácticamente igual.

Entregables: arquitectura revisable, pruebas ejecutadas y paridad demostrada con Codex.

### Entrega 3 — Claude Code

Investigar interfaces reales, implementar conexión reversible, añadir detección de estados y apertura, probar permiso y dos tareas simultáneas, después combinar con Codex. Añadir selector de fuentes solo cuando tenga proveedores funcionales.

Entregables: segunda integración utilizable, guía breve y tabla de capacidades.

### Entrega 4 — Beta compartible

Empaquetar una versión identificada, probarla en otro Mac, entregar a amigos con checklist y recoger incidencias. Incorporar solo correcciones necesarias antes de abrir un bloque de funciones nuevo.

Entregables: DMG, notas de versión, instrucciones y resultados de testers.

### Entrega 5 — Extensiones

Con evidencia de cómo se usan Q y las integraciones, estabilizar `.qmode`, construir el puente local y un ejemplo SDK. Añadir MCP como cliente del mismo contrato.

Entregables: un colaborador consigue añadir una funcionalidad propia sin tocar firmware.

## 19. Definición de terminado y mantenimiento

Una tarea se considera terminada cuando el comportamiento solicitado existe, sus casos relevantes se prueban, el resultado se observa en la superficie real cuando corresponde, y documentación/limitaciones reflejan lo entregado.

Para integraciones, incluir objetivo equivocado, fuente ausente y eventos antiguos. Para firmware, incluir hardware real. Para distribución, incluir otro equipo. Una compilación correcta es un requisito técnico, no evidencia suficiente de todos esos resultados.

Cada entrega debe registrar commit, versión, pruebas ejecutadas, pruebas pendientes y cambio observable. Commit/push y publicación de artefactos se harán como pasos explícitos del flujo de entrega autorizado; escribir este roadmap por sí solo no publica una release.

Revisar el roadmap después de cada hito y de las primeras sesiones de testers. Mover trabajo terminado a las guías; archivar hipótesis descartadas; reordenar según fallos reales y uso. Mantener identificadores del backlog para conservar trazabilidad.

## 20. Visión posterior a 1.0

Una vez que Q sea fiable y fácil de extender, evaluar más agentes, integración con builds, más plataformas, múltiples dispositivos y una biblioteca de modos compartidos. Cada expansión debe responder a una necesidad observada y tener un responsable de mantenimiento.

Windows o Linux requieren trabajo propio de bandeja, permisos, instalación, descubrimiento USB e integraciones. Conectividad inalámbrica o batería implican revisar hardware, energía, emparejamiento y recuperación. No son ampliaciones triviales del código actual.

La dirección recomendada es convertir Q en una interfaz física pequeña para procesos digitales: entender cuándo algo avanza, cuándo necesita atención y qué acción corresponde. El criterio para añadir una función será si hace esa experiencia más útil y más fiable con las tres luces y el botón que ya existen.
