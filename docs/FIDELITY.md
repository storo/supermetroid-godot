# Requisitos de fidelidad del remake completo

El encargo es reconstruir Super Metroid en Godot, mejorar los assets extraídos de la ROM y mantener todo el juego. Una importación de salas o una demo no cierra ese objetivo.

| Requisito | Evidencia actual | Estado |
| --- | --- | --- |
| Ejecución nativa de Godot | CharacterBody2D, StaticBody2D, GDScript, shaders; pruebas de ejecución | Base implementada |
| Extraer assets de la ROM proporcionada | SHA-256, tiles 4bpp, paletas, DMA/OAM, manifiesto | Implementado para tilesets, 19 conjuntos de Samus (nueve movimientos en ambos sentidos y pose frontal), nave, ascensor y atlas de enemigos |
| Mejorar gráficos manteniendo identidad | Scale2x por tile/frames, fondo nuevo de Crateria en Landing Site, pared de Ceres redibujada en tres salas/dos estados, 66 tiles BG2 de Brinstar verde, 16 de Big Pink y 44 de Parlor en dos estados, con IDs/giros/scroll/paleta nativos, alternancia F1 | Cinco familias de fondo integradas; redibujado completo de assets pendiente |
| Conservar todas las salas y geometría | 261 salas / 322 estados; auditoría nativa | Datos importados; comportamiento y fondos originales incompletos |
| Conservar todas las animaciones de Samus | 19 conjuntos renderizados desde OAM; gráficos específicos para izquierda/derecha y pose frontal del ascensor | Incompleto; faltan poses, tiempos y asimetrías |
| Física equivalente a SNES | Constantes originales de gravedad/salto/carrera; pendientes y cuadrantes BTS de ROM | Incompleto; no hay comparación por fotograma |
| Puertas, elevadores, estaciones y PLM | Restricciones por color, condiciones de jefe/cuota y 14 extremos de ascensor; una estación con guardado/recarga y bloques de bombas de Parlor verificados en C/Godot | Incompleto; demás estaciones y estatua de Tourian pendientes |
| Enemigos y sus IA originales | 154 atlas y parámetros; tres IA aproximadas; piratas grises de suelo/pared con instrucciones, frames e hitboxes de ROM y rutinas nativas | Incompleto; faltan las demás familias y comparación por fotograma |
| Jefes y minijefes | Assets crudos y rutinas C integradas; retirada de Ridley de Ceres por salud baja y derrota original de Bomb Torizo en Godot | Incompleto; demás jefes y variantes por verificar |
| Mejoras, armas y restricciones originales | Morph Ball, misiles, bombas y primer tanque de energía; tanque inferior de Big Pink, Charge Beam y carga/disparo nativos comprobados C/Godot | Incompleto; resto de mejoras y armas por verificar |
| Líquidos, calor, arena y tipos de bloque | Datos disponibles; colisiones sólidas y pendientes | Incompleto |
| Ceres, historia, eventos y cambios de estado | 61 selectores de ROM en GDScript; Ceres → Ridley → escape → llegada controlable a Landing Site en la integración C/Godot | Tramo Ceres verificado en la integración; historia y campaña restantes incompletas |
| Música y efectos originales | Efectos sintetizados en GDScript; reproductor SPC nativo con audio audible durante el recorrido de Ceres | Repertorio y paridad de audio completos pendientes |
| Guardado, menú, mapa | Guardado JSON, mapa y controles en GDScript; estación de Crateria, SRAM original de 8192 bytes y recarga con equipo/eventos/movimiento comprobados en la integración C/Godot | Una estación nativa verificada; demás rutas y estaciones pendientes |
| Campaña completa de principio a fin | No hay recorrido completo ni final funcional | Pendiente |
| Verificación del juego completo | Auditoría de salas y pruebas básicas; capturas | Incompleto |

## Orden de trabajo pendiente

1. Completar la extracción de poses, fondos, gráficos de PLM y metadatos de eventos; conservar las direcciones originales como trazabilidad.
2. Ampliar la continuación nativa verificada desde Crateria Save hasta Brinstar verde hacia Spore Spawn y Kraid, con puertas/elevadores/objetos reales y sin habilitar equipo de prueba.
3. Implementar el sistema de eventos y selección de estado de sala; establecer pruebas por escena original y condición de progresión.
4. Portar las armas, mejoras, colisiones especiales, líquidos y estaciones; comparar controles y física a 60 Hz con capturas/datos del original.
5. Portar todas las familias de enemigos y jefes, con estados y vulnerabilidades originales.
6. Reconstruir Ceres, historia y final; importar/reproducir música y efectos originales.
7. Redibujar las familias de assets preservando siluetas, puntos de anclaje, límites y animación; validar cada reemplazo junto al original.
8. Verificar la campaña completa, rutas, secretos, todos los objetos y condiciones de final antes de declarar el remake completo.

La prueba `--progression-test` comprueba los selectores, su prioridad y persistencia. `--pirate-test` instancia los cinco piratas de Pit, ejecuta sus ataques y los derrota con proyectiles; comprueba el evento y las dos puertas de cuota. No prueba un recorrido completo. Los datos se leen de los selectores de $8F:E5E6–E678 y del byte tras el terminador de población de enemigos. Las condiciones de puerta gris siguen la tabla de $84:BE4B–BE57 y el campo de argumento definido en $84:C794.

Los piratas grises interpretan las listas de $B2:ECC0–EE40 y $B2:FB4C–FC68. Las rutinas de patrulla, disparo, reacción a proyectiles y salto entre paredes se adaptan a cuerpos/collisiones de Godot, conservando parámetros y tiempos de las listas. La resolución de colisiones en pendientes, el orden exacto por fotograma, el generador aleatorio SNES, el sistema de slots de proyectiles, congelación, drops y sonido original todavía no tienen equivalencia verificada. La prueba de combate no debe presentarse como prueba de IA idéntica a SNES.

Los ascensores siguen $A3:94D6–962E: dos cuadros cada dos ticks, 1.5 píxeles/tick, Samus a 26 píxeles sobre la plataforma y posición de entrada leída de `parameter2`. La demora descendente de 48 ticks procede de $82:E18E. La prueba ejecuta un viaje real de ida y vuelta con input/física del motor y los 14 trayectos con pasos nativos deterministas. El fundido, cámara, sonidos y orden de transición no tienen comparación por fotograma con SNES; los requisitos de acceso de la campaña siguen dependiendo de sus PLM, jefes y eventos pendientes.

La ROM debe permanecer intacta. El modo de exploración es una herramienta de inspección; no representa la progresión de la campaña.

`verify_bombs.py` verifica una partida nueva de 68964 ticks hasta bombas y
Bomb Torizo. Reproduce un prefijo registrado de botones, vuelve por Climb/Parlor
despiertos, cruza el pasaje de Morph Ball, usa drops para recuperar energía,
abre la puerta roja con cinco misiles y recoge las bombas. El jefe recibe daño
desde sus 800 puntos originales hasta la secuencia que activa el bit de derrota.
Samus coloca una bomba, espera su explosión y recupera una pose de pie. Godot
coincide con el registro C en cada tick y siete capturas originales suman 401408
píxeles RGB idénticos al oráculo offline. No se modifica memoria de juego ni
equipo para avanzar. El informe `docs/qa/native_bomb_verification.json` mantiene
`whole_campaign_verified: false`: la evidencia cubre este recorrido, no todos
los combates, la salida de la puerta gris, estaciones, secretos o el final.

`verify_station.py` prolonga esa evidencia hasta Terminator y Crateria Save.
Comprueba 76436 ticks desde una partida nueva, la salida gris, bloques de
bombas, energía máxima de 199, diálogo y escritura original de la estación 1.
La SRAM de 8192 bytes coincide entre C y Godot. Después de cerrar y abrir el
núcleo, 1247 ticks de menús/carga conservan sala, salud, equipo, munición y
eventos/jefes; Samus vuelve a moverse tras la animación de entrada. Los informes
`docs/qa/native_station_*` limitan el resultado a esa ruta, tanque y estación.
Las seis capturas de esa prueba suman 344064 píxeles RGB idénticos al oráculo
offline. La campaña completa, demás estaciones, secretos y final siguen pendientes.

`verify_green.py` comprueba 5316 ticks de continuación desde esa SRAM original.
La genera de nuevo mediante botones desde el arranque, verifica el hash del
guardado ya certificado C/Godot y carga una copia por los menús originales.
Sube Parlor, rompe su pared con bombas, cruza Terminator y Green Pirates Shaft,
atraviesa Lower Mushrooms y viaja en el ascensor hasta el pozo de Brinstar verde.
Compara 25 campos por tick, preserva equipo/eventos/jefes y prueba movimiento
al llegar. Siete capturas suman 401408 píxeles RGB idénticos al oráculo.
El daño es real: llega con 9/199 de energía. No prueba todas las rutas, el
combate de los piratas verdes, Spore Spawn, Kraid ni la campaña restante.
Informe: `docs/qa/native_green_verification.json`.

La mejora de 66 tiles BG2 en `9AD9/9AE6` se comprobó en esa continuación,
con nueve capturas original/restaurada y 516096 píxeles RGB exactos, 1830828
píxeles protegidos sin cambios y varias alturas con el fondo visible. Un
cálculo independiente de 433838 muestras verifica la selección del atlas,
giros y CGRAM con un nivel RGB de error máximo; se permite hasta dos por
redondeo. La presentación deja el estado nativo intacto. Las regresiones de
Ceres/Crateria pasaron. Este alcance no demuestra el resto de assets o campaña;
informe `docs/qa/native_green_art_verification.json`.

## Investigación de la lógica C original

`tools/native_probe/` compila la referencia MIT `snesrev/sm` en la revisión
`578f90b3cc49557bb70060ad033bb90b8cf8ac50`, sin su aplicación SDL. Los puntos de
ejecución de opcodes de CPU y SPC abortan si se invocan. La prueba recorre menús,
introducción y la primera sala de Ceres con movimiento, disparos y audio nativo.
Esta evidencia permite investigar una integración de las rutinas originales en
Godot, pero no demuestra fidelidad completa ni elimina todas las dependencias de
hardware de la referencia. Su infraestructura aún usa registros, DMA, PPU y DSP;
en ese diagnóstico inicial todavía faltaba la integración/renderizado de Godot.
Los resultados del diagnóstico inicial están en `docs/qa/native_probe.json`.
La integración posterior en `native/` registra `SmNativeCore` en Godot y excluye
los intérpretes CPU/SPC del build. Godot recibe VRAM/CGRAM/OAM y compone los tiles,
sprites y fondo de Mode 7 mediante shaders. Se verificaron 18000 ticks en la
extensión, llegada a Ceres, movimiento/audio, propiedad única y cierre/reinicio;
hay capturas del ascensor inicial. El renderer de Godot ya recibe registros y
paletas por línea, compone main/subscreen, recupera el HUD de Ceres y aplica
ventanas, color math y brillo. Una herramienta offline compara capturas concretas
con el renderer de referencia, sin tolerancia RGB; el oráculo no se usa durante
el gameplay. El informe `docs/qa/native_raster_comparison.json` conserva el alcance
de esa evidencia. Falta verificar más modos, transiciones y efectos, salida hires,
cambios de VRAM/OAM durante líneas visibles y rotación OAM por línea.
Esta escena independiente no sustituye la
campaña principal ni completa los requisitos de la tabla. Consulta
`native/README.md` para reproducirla y `tools/native_probe/README.md` para el
diagnóstico anterior.

`verify_campaign.py` registra 16836 controles normales de menús, introducción,
las seis salas de Ceres, combate con Ridley, retirada por salud baja, cuenta
regresiva, subida y llegada a Landing Site con movimiento de Samus. Godot reproduce
ese input y coincide con el ejecutable C en estado, sala, posición, pose, salud y
evento/timer para todos los ticks. Cuatro checkpoints de dibujo coinciden en
229376 píxeles RGB con el oráculo de PPU offline; se conservan capturas originales
y mejoradas a 2×. El informe es `docs/qa/native_campaign_verification.json`.

Esta evidencia verifica un recorrido y el enlace de Godot con la referencia C.
No prueba la paridad de lógica con la CPU SNES, la retirada por daño a Ridley,
todos los fotogramas, todos los efectos o el resto de la campaña. El menú permite
entrar a esta escena cuando están presentes ROM/binario, y F10 vuelve liberando
el núcleo. La prueba de navegación usa una SRAM distinta de la partida del usuario.

`verify_zebes.py` amplía ese recorrido a 21959 ticks con las salas iniciales de
Zebes y la recogida de Morph Ball. El controlador usa botones normales, cierra el
mensaje original, transforma a Samus y comprueba su desplazamiento rodando.
Godot coincide con la referencia C por tick en estado, sala, posición, pose,
salud, inventario y tipo/velocidad de movimiento. Cuatro checkpoints adicionales
se comparan en RGB sin tolerancia con el oráculo offline; el informe es
`docs/qa/native_zebes_verification.json`. Los misiles y el despertar se comprueban
con los recorridos posteriores descritos abajo; la campaña restante sigue pendiente.

La campaña nativa tiene sus doce botones SNES accesibles por teclado y mando,
incluidos Start, Select y cancelar arma, cruz y stick izquierdo. La prueba
`native_input_test.gd` envía eventos a Godot y verifica sus máscaras, combinaciones,
liberación, zona muerta y registro sin duplicados al reabrir la escena.

`verify_missiles.py` continúa hasta Construction Zone y First Missile en 23436
ticks de una partida nueva. Comprueba bloques y pasajes bajos, tanque/estatua,
mensaje original, selección, un disparo, capacidad 5/munición 4, cancelación y
movimiento posterior. Godot coincide por tick con la referencia C en los estados
y en los nuevos diagnósticos de inventario, proyectiles, cuotas y eventos.
Cuatro capturas suman 229376 píxeles RGB idénticos al oráculo offline, incluido
el mensaje con cambios de BG3 por HDMA. El informe es
`docs/qa/native_missile_verification.json`. Las bombas y demás mejoras/combates
de la campaña siguen pendientes.

`verify_awaken.py` prolonga el recorrido a 26570 ticks, sube por Construction
Zone, vuelve a Crateria por el ascensor y derrota los cinco piratas originales
de Pit. La sala selecciona el estado $9787 al tener Morph Ball y misiles. Se
comprueba que el evento 0 permanece apagado con menos de cinco derrotas y se
activa al cumplir la cuota, sin escrituras de RAM del controlador. Godot coincide
por tick con el ejecutable C; cuatro capturas coinciden en 229376 píxeles RGB
con el oráculo offline. `docs/qa/native_awaken_verification.json` registra ese
alcance. Esto no verifica todavía la salida de Pit, estaciones, bombas,
Bomb Torizo, otros jefes, final o la campaña completa.

`verify_art.py` verifica el fondo nuevo en Landing Site durante gameplay. La
composición protege HUD/BG1/sprites y restaura el modo original con F1; se compara
ese original contra la PPU offline. El parallax y la selección por sala/estado
se comprueban con el mismo snapshot, sin escribir al núcleo de juego. El informe
`docs/qa/native_art_verification.json` registra diferencias por capa y límites
del alcance. Esto integra el fondo ya generado, no completa el redibujado de
tiles, personajes, enemigos ni otros fondos.

La mejora del fondo de Big Pink (`9D19/9D26`) añade 16 tiles BG2 redibujados
desde VRAM/CGRAM. `verify_pink_art.py` regenera la partida de Crateria desde
inputs normales y reproduce 8241 ticks con 25 campos idénticos C/Godot: cinco
piratas verdes, drops de munición, puerta roja, barrera de bombas de Dachora
y movimiento dentro de Big Pink. Se conservan la salud y el equipo originales.

Las seis capturas original/restaurada suman 344064 píxeles RGB idénticos al
oráculo offline. Los 638316 píxeles protegidos conservan HUD, terreno y sprites.
Un cálculo independiente comprueba 562644 muestras del atlas con error máximo
de un nivel RGB, incluidos giros, IDs y CGRAM. Scroll, fade, blanking y
exclusiones también pasan; las regresiones de Brinstar verde, Ceres y Crateria
pasaron. La ROM y SRAM fuente permanecen intactas. Esta evidencia no cubre
Spore Spawn, mejoras posteriores ni la campaña completa; informes en
`docs/qa/native_pink_art_*`.

`verify_charge.py` prolonga la continuación hasta el tanque inferior de Big
Pink y Charge Beam. El recorrido de 10072 ticks conserva 29 campos de estado
por tick entre C y Godot, incluidos rayo equipado, contador de carga,
proyectiles cargados y `time_is_frozen_flag`. Rompe el paso de bombas y la
esfera de la estatua, conserva los avisos de recogida y recupera el control.
La carga supera el umbral nativo de 60 ticks; el proyectil cargado permanece
activo 17 ticks y no consume misiles. Termina con capacidad 10, munición 5,
rayo `1000`, equipo `1004`, energía 24/199 y eventos/jefes originales.

Las diez capturas suman 573440 píxeles RGB idénticos al oráculo offline y su
presentación deja el estado del núcleo intacto. La SRAM se regenera desde
inputs de partida nueva y coincide con la certificada C/Godot. ROM y SRAM
fuente permanecen intactas; el ciclo de cierre/reinicio del núcleo pasó.
El tanque superior de Big Pink, Spore Spawn, Kraid y la campaña restante
siguen sin verificar. Evidencia: `docs/qa/native_charge_verification.json`.

`verify_parlor_art.py` comprueba los 44 tiles redibujados de Crateria Rocks
usando los estados reales de Parlor `92FD/9314` y `92FD/932E`. Reproduce
23433 ticks: tres checkpoints del prefijo de partida nueva y cuatro de
la continuación desde Crateria Save. Los 5316 ticks de esta continuación
conservan 25 campos por tick entre C y Godot; las capturas conservan además
posición, cámara, pose, salud y equipo originales. El dibujo se captura
en un SubViewport propio y no modifica el estado del núcleo.

Las siete capturas suman 401408 píxeles RGB originales/restaurados idénticos
al oráculo offline. Los 755560 píxeles protegidos mantienen HUD, terreno
y sprites. El cálculo independiente comprueba los 44 IDs y cuatro modos
de giro, además de CGRAM/scroll, con error máximo de un nivel RGB. Fundido,
blanking y exclusiones pasan. Crateria, Ceres, Brinstar verde y Big Pink
pasaron sus regresiones después de compartir el sampler del atlas activo.
ROM y SRAM fuente quedan intactas. El estado del escape final `9348`, las
demás salas de esta biblioteca, Spore Spawn y la campaña completa siguen
pendientes. Evidencia: `docs/qa/native_parlor_art_*`.
