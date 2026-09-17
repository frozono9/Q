# Q: plan de clientes portables con macOS como plataforma principal

Estado: propuesta de implementación; este documento no implica soporte ya disponible.
Fecha: 17 de septiembre de 2026.
Rama: `feature/portable-clients`.
Base inspeccionada: `5c7a1e5c6a48c661d4dde22840372fe246af5884`.

## 1. Objetivo y límites

Añadir clientes para Windows y Linux que reutilicen la lógica de Q y acompañen
su evolución con el menor mantenimiento posible. macOS conserva la experiencia
principal, su interfaz nativa, sus integraciones y su calendario de publicación.

El trabajo inicial se desarrolla en esta rama y en un worktree separado.
Publicar la rama no autoriza fusionarla en `main`. Esta entrega añade únicamente
el plan: no modifica código, firmware, pipelines ni configuración de repositorio.

No se promete paridad inmediata entre sistemas ni que una compilación automática
adapte funciones exclusivas de macOS. Compartir lógica reduce trabajo repetido;
las interfaces y las integraciones de cada sistema siguen necesitando desarrollo.

## 2. Punto de partida comprobado

- `Package.swift` define `QCore` con `Sources/Q/Models` y `Sources/Q/Device`.
- Los modelos y `QSerialProtocol.swift` usan Foundation y son candidatos a
  reutilización. Su portabilidad todavía debe verificarse compilando y probando.
- `SerialQDevice.swift` y `VirtualQDevice.swift` usan Combine y OSLog; el
  transporte existente también asume descubrimiento y configuración de Mac.
- `QAppModel.swift` mezcla coordinación de modos con AppKit, observación,
  persistencia e integraciones del sistema. El núcleo actual no contiene todo
  el comportamiento necesario para ejecutar el producto por sí solo.
- Existen pruebas de modelos, escenas, protocolo, prioridades, Pomodoro y
  gestos; algunas pruebas dependen de implementaciones específicas de Mac.
- La documentación de esta revisión declara app 0.3.0, firmware 0.2.3 y
  protocolo serie 1. Son versiones independientes.
- Se ha verificado desde Windows el handshake y la aceptación de escenas con
  una unidad que informa firmware 0.2.2. Esto no valida todavía un cliente
  Windows, el firmware 0.2.3 en hardware ni ninguna ejecución en Linux.

Referencias del repo: [guía del proyecto](../PROJECT_GUIDE.md),
[firmware](../Firmware/README.md), [roadmap principal](../ROADMAP.md) y
[formato de modos](custom-mode.schema.json).

## 3. Decisiones de arquitectura

### 3.1 Conservar la aplicación Mac

Mac sigue usando SwiftUI/AppKit y ejecutando el núcleo dentro de su proceso.
No se introduce un servicio auxiliar obligatorio, una interfaz web ni una
dependencia de Windows/Linux para arrancar, compilar o publicar la app Mac.
Las nuevas funciones específicas de Mac pueden seguir apareciendo primero allí.

### 3.2 Compartir fuentes Swift, no copias

La frontera deseada separa modelos, reglas, escenas y codificación de protocolo
de transportes, presentación y acciones del sistema. Los nombres concretos de
los nuevos targets se decidirán en la primera fase; no son una API comprometida.

Se procurará conservar rutas, nombres e imports actuales de Mac. Antes de mover
archivos se probará una separación mínima de targets y dependencias, manteniendo
una fachada compatible para los consumidores actuales de `QCore` si hace falta.
No se mantendrán árboles de fuentes duplicados ni copias generadas del motor.
Los condicionales de plataforma se concentrarán en composición y adaptadores.

La lógica que aún vive en `QAppModel` se extraerá por funciones concretas, con
pruebas de comportamiento, evitando una reescritura general del archivo.

### 3.3 Motor portable y clientes

Windows y Linux tendrán un ejecutable que use el núcleo compartido, gestione
el dispositivo y ofrezca operaciones semánticas: seleccionar modo, aplicar una
escena, recibir gestos y consultar estado/capacidades. Un CLI permitirá validar
estas operaciones antes de construir la interfaz gráfica.

La interfaz de Windows/Linux compartirá código donde sea viable y permanecerá
separada de SwiftUI. Su tecnología se elegirá después de demostrar compilación,
empaquetado y USB en ambos sistemas. Si necesita un proceso auxiliar, se usará
un contrato local versionado, preferentemente stdio o IPC del sistema, sin
exponer un servicio de red ni ejecutar comandos arbitrarios desde perfiles.

### 3.4 Adaptadores y capacidades

Cada plataforma implementa transporte USB, persistencia, notificaciones, apertura
de aplicaciones y proveedores de actividad. Un modo no presupone que todas sus
acciones existan en todos los sistemas. La UI mostrará explícitamente las
capacidades disponibles; una función ausente no se presentará como operativa.

El modo elegido conserva la propiedad de las luces y el botón. Las integraciones
en segundo plano no pueden sustituirlo. Se preservan los principios de datos
locales y diagnósticos sin prompts ni contenido de conversaciones.

## 4. Secuencia de implementación

### P0 — Baseline y prueba de portabilidad

- Fijar una versión de Swift compatible con el flujo actual de Mac.
- Ejecutar la compilación y las pruebas existentes en Mac y registrar resultados.
- Inventariar dependencias Apple y construir el subconjunto compartible en
  Windows y Linux usando las mismas fuentes.
- Separar pruebas portables de pruebas de adaptadores Mac sin eliminar cobertura.
- Probar los scripts de compilación alternativos de Mac, además de SwiftPM.
- Registrar una decisión breve sobre límites de módulos y cambios mínimos.

Criterio de salida: modelos y protocolo compilan y pasan pruebas en los tres
sistemas; la app Mac y su empaquetado siguen funcionando. Si Swift o una
dependencia impide este resultado, documentar el bloqueo y resolver la decisión
antes de elegir UI o prometer distribución portable. No afirmar que los checks
de Mac/Linux pasaron si no se dispone del entorno correspondiente.

### P1 — Transporte y CLI Windows/Linux

- Descubrir candidatos USB y confirmar identidad con `H|1`, sin confiar solo
  en VID/PID ni fijar COM9 o una ruta Linux concreta.
- Implementar framing de líneas parciales, límites de buffer, timeouts,
  confirmaciones de escenas, heartbeat y todos los gestos admitidos.
- Tratar desconexión, reconexión, suspensión, puerto ocupado y permisos.
- Seleccionar una unidad por identidad estable; evitar que dos instancias
  compitan por el mismo dispositivo y pedir selección si hay varias unidades.
- Exponer CLI para estado, escenas, apagado, prueba de luces y eventos del botón.
- En Linux, documentar acceso al dispositivo con permisos mínimos. No ejecutar
  el cliente habitualmente como root ni exigir cambios globales de permisos.

Criterio de salida: pruebas de transporte simulado y una sesión real documentada
en Windows y Linux con luces, gestos, retirada/reconexión y pérdida de heartbeat.
La ejecución de CI sin hardware no sustituye esta validación.

### P2 — Comportamiento compartido y ajustes

- Extraer solo la coordinación necesaria para disponibilidad manual, Pomodoro,
  relajación y escenas personalizadas, conservando el comportamiento de Mac.
- Usar reloj inyectable para verificar pausas, vencimientos, reposo y reanudación.
- Reutilizar reglas de prioridades, brillo y modos existentes.
- Versionar los ajustes portables y sus migraciones; separar datos de usuario
  del paquete reemplazable y guardar copia previa a una migración.
- Validar `.qmode`; indicar acciones de Mac no disponibles en Windows/Linux sin
  ejecutarlas ni borrar silenciosamente datos que no se comprendan.

Criterio de salida: mismas entradas producen mismas escenas y transiciones en
los tres sistemas. Reiniciar o actualizar conserva ajustes. El CLI demuestra
los modos antes de conectarlos a la UI.

### P3 — Interfaz portable e integraciones iniciales

- Hacer una prueba acotada de UI Windows/Linux: tamaño y dependencias del paquete,
  accesibilidad, bandeja, ventanas, ciclo de vida y comunicación con el motor.
- Registrar la elección técnica y empaquetar una muestra en entornos limpios.
- Implementar estado de conexión, modos, brillo, prueba de luces/botón y ajustes.
- En Linux, mantener una ventana accesible aunque el escritorio no ofrezca bandeja;
  verificar las sesiones gráficas que se declaren soportadas.
- Añadir proveedores de agentes cuando existan fuentes locales verificables para
  cada plataforma. Separar detección de actividad de las acciones para enfocar apps.
- Tratar Meetings, control del micrófono y dictado como adaptadores posteriores,
  con pruebas por proveedor. No simular paridad ni inferir éxito de un atajo.

Criterio de salida: alguien sin herramientas de desarrollo puede abrir el cliente,
conectar Q, usar los modos básicos y entender qué integraciones están disponibles.

### P4 — Paquetes y distribución repetible

- Windows: ZIP que incluya ejecutable y dependencias redistribuibles necesarias;
  verificar en un equipo sin Swift, Python ni herramientas de compilación.
- Linux: paquete portable con una base de compatibilidad declarada. Evaluar el
  SDK estático para el motor; comprobar por separado dependencias de la UI,
  permisos USB, bandeja y diferencias de escritorio.
- Matriz inicial propuesta: Windows 11 x64 y Ubuntu 24.04 LTS x86_64; añadir una
  segunda distribución Linux antes de anunciar soporte Linux amplio. ARM64 se
  publicará solo cuando se compile y pruebe; Mac mantiene sus destinos actuales.
- Producir artefactos con versión, revisión de origen, arquitecturas, capacidades,
  versiones de protocolo admitidas, checksums y notas de limitaciones.
- Validar sustitución del paquete conservando ajustes y una recuperación mediante
  backup si la versión anterior no puede leer ajustes migrados.
- Evaluar firma de Windows y su distribución; no prometer ausencia de avisos del
  sistema. Un actualizador automático y flasheo integrado quedan fuera del MVP.

Criterio de salida: instalación por extracción y ejecución, actualización manual
verificada y pruebas de humo en máquinas limpias. Publicar solo las plataformas
que hayan completado su validación.

## 5. Versiones y contrato de compatibilidad

Mantener separados versión de app, revisión del núcleo, firmware, protocolo USB,
ajustes y, si existe, IPC local. Coincidir en número de versión no prueba
compatibilidad. Cada artefacto identificará el commit que contiene y sus límites.

Conservar el protocolo 1 durante la primera implementación. No cambiar códigos
de animación, significado de campos ni gestos existentes. Un cliente antiguo
puede seguir usando sus funciones si el firmware conserva ese contrato, pero
no recibe automáticamente funciones nuevas de la aplicación.

La negociación de capacidades es una evolución posterior, no una función que
el firmware actual ya ofrezca. Debe tener fallback para dispositivos existentes
y pruebas antes de usar comandos nuevos. Un cambio incompatible exige versión
de protocolo nueva y una política de convivencia explícita.

Mantener fixtures de handshake, escenas y eventos de versiones soportadas. Las
pruebas cubrirán entradas fragmentadas, inválidas y extensiones desconocidas.
No actualizar firmware como requisito del primer cliente si el protocolo actual
resuelve sus necesidades. Todo flasheo futuro debe identificar la unidad y
comprobar la versión tras reconectar.

## 6. CI y relación con main

1. Trabajar inicialmente en esta rama, con commits pequeños por fase y función.
2. Incorporar `origin/main` regularmente mediante merges normales, sin reescribir
   una rama publicada que otros puedan estar usando.
3. Proponer por separado los cambios mínimos del núcleo que convenga integrar
   upstream. Evitar mezclar extracciones, formateo y funcionalidades nuevas.
4. Mantener el flujo Mac existente. Añadir workflows portables separados con
   disparo manual y filtros para fuentes compartidas/clientes portables.
5. Probar el núcleo en macOS, Windows y Linux y cada adaptador en su plataforma.
   Un fallo portable impide publicar su artefacto; no detiene la release Mac.
6. Acordar con el mantenedor qué checks serán obligatorios para cambios del núcleo.
   Este plan no modifica branch protection ni impone checks nuevos a `main`.
7. Compilar candidatos portables desde nuevas revisiones de Mac y publicar solo
   tras checks satisfactorios. Un fallo deja un estado visible y conserva la
   última versión válida; nunca anuncia paridad o éxito inexistente.

No hace falta abrir un PR hacia `main` para publicar este plan y su rama. Cuando
P0 produzca una extracción pequeña comprobada, preparar un PR independiente de
borrador con el diff, evidencia de regresión Mac y límites. La integración en
`main` requiere una decisión posterior del mantenedor; no activar auto-merge.

Una rama permanentemente divergente exige mantenimiento. La reducción sostenida
de trabajo depende de incorporar una frontera compartida mínima aceptada por Alex.
Si esto no se acepta, documentar el coste de mantener el cliente downstream en
lugar de prometer adaptación automática de cualquier actualización futura.

## 7. Criterios de validación y responsables

| Área | Evidencia necesaria | Responsabilidad propuesta |
| --- | --- | --- |
| Regresión Mac | Build, tests, empaquetado y prueba de uso | Colaborador portable aporta evidencia; Alex revisa cambios Mac |
| Motor compartido | Tests deterministas en tres sistemas | Mantenimiento portable, en coordinación con Alex |
| USB | Tests simulados y sesiones con hardware por SO | Mantenimiento portable y testers con hardware |
| Windows/Linux | Paquetes en entornos limpios y capacidades verificadas | Mantenimiento portable |
| Firmware/protocolo | Compatibilidad documentada y pruebas en unidad real | Mantenedor de firmware con colaboración portable |
| Release | Commit, checks, plataformas y limitaciones identificables | Responsable de cada cliente |

Las responsabilidades son una propuesta de colaboración, no compromisos asumidos
por Alex. No se añaden servicios externos, cuentas ni dependencias del runtime
portable al uso normal de la aplicación Mac.

## 8. Primer bloque de trabajo

- [ ] Registrar baseline de compilación/tests Mac y disponibilidad de entornos.
- [ ] Diseñar y probar la separación mínima de fuentes/targets compartibles.
- [ ] Ejecutar pruebas de modelos y protocolo en los tres sistemas.
- [ ] Revisar el diff Mac y documentar la decisión de arquitectura de P0.
- [ ] Implementar CLI y transporte de Windows, seguido del de Linux.
- [ ] Registrar pruebas reales del aparato y continuar con P2.

No se empezará una migración de UI ni un servicio permanente antes de cerrar P0.
No se fusionará esta rama ni se publicarán cambios en `main` como parte de la
publicación de este documento.

## 9. Referencias técnicas

- [Plataformas soportadas por Swift](https://www.swift.org/platform-support/).
- [SDK estático de Swift para Linux](https://www.swift.org/documentation/articles/static-linux-getting-started.html).
- [Runners de GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job).

Estas referencias orientan las pruebas; no sustituyen la verificación del código
y los artefactos de Q en cada sistema.
