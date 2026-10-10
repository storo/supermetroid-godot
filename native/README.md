# Núcleo de gameplay compilado para Godot

La extensión `SmNativeCore` integra las rutinas C de `snesrev/sm` y el reproductor
de audio nativo. Es una integración en desarrollo, separada de la escena principal
GDScript. **No demuestra que la campaña completa esté terminada o verificada.**

```sh
sh native/setup.sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/native_probe/godot_test.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . scenes/native_campaign.tscn
```

El binario actual se construye para este Mac x86_64 con clang/CMake y bindings de
Godot 4.5 (probado en 4.7.1). Otras plataformas necesitan su build y entrada de
`.gdextension`. Las revisiones se fijan en `setup.sh`: referencia C
`578f90b3cc49557bb70060ad033bb90b8cf8ac50` y godot-cpp
`e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`.

`native/.gdignore` evita que Godot intente cargar automáticamente un binario
inexistente al abrir una copia limpia del repo. La escena nativa carga la
extensión explícitamente y mantiene su recurso mientras usa el núcleo; la escena
principal GDScript se puede importar y ejecutar sin compilarla.

La escena independiente conserva los menús y la introducción ejecutados por el
núcleo. Enter envía Start; espacio/Z envía A; J/X envía X; Shift envía B; K envía
Select para elegir misiles; Q/E envían R/L. A/D o flechas y W/S controlan la cruz.
Retroceso envía Y para cancelar la selección de arma. El mando usa A para salto,
B para carrera, X para disparo, Y para cancelar, R/L para apuntar, Start/Back para
Start/Select, cruz y stick izquierdo para movimiento. Estas acciones nativas
tienen bindings independientes de la escena GDScript y no se duplican al volver
a abrirla. `native_input_test.gd` comprueba eventos reales de teclado, botones y
stick, combinaciones, liberación y zona muerta.
F1 alterna arte; Escape congela la prueba. Las acciones de Morph Ball y bombas
siguen los botones originales del núcleo (Down y X). No hay equipo concedido por
la escena. Después de conseguir Charge Beam, mantener J/X carga el rayo y
soltarlo dispara; se conserva el umbral original de 60 ticks. La SRAM usa
`user://native_campaign.srm` y no sustituye el JSON de la
escena principal. Al arrancar, el host lee la SRAM existente antes de los menús
originales para poder continuar desde la estación guardada. El
`--native-core-capture` usa SRAM de prueba independiente,
recorre la introducción mediante input y captura el ascensor inicial de Ceres.

El menú de la escena principal ofrece **Jugar desde Ceres** cuando existen la ROM
y el binario de este Mac. F10 vuelve a ese menú y libera el núcleo/audio. La
comprobación de navegación usa `--native-core-ui-test` con su propia SRAM temporal.

## Arquitectura

- `core/host.c` inicializa memoria y dispositivos, ejecuta `RunOneFrameOfGame` y
  procesa DMA/HDMA/IRQ. Renderizar píxeles en la PPU de referencia está deshabilitado.
- `core/devices.c` contiene sólo estructuras de registros/lifecycle requeridas por
  ese host. **Los archivos con intérpretes de opcodes CPU/SPC y la infraestructura
  de comparación/ASM no se compilan.** Cualquier intento de ejecutar un opcode
  falla en el límite de la API. Bang selecciona directamente una de sus tres
  funciones C usando el parámetro original; otros dispatch inesperados fallan.
- `bridge.cpp` registra una clase RefCounted, verifica el SHA-256 de la ROM,
  controla la propiedad única del núcleo, expone snapshots y entrega 534 frames
  de audio estéreo por tick (32040 Hz a 60 ticks/s). Todas las llamadas al núcleo
  ocurren en el hilo de gameplay; el audio de Godot recibe copias de muestras.
  `get_state()` expone un diagnóstico de lectura sin copiar texturas: posición,
  estado, salud, equipo, evento de Ceres, cuenta regresiva y primer slot enemigo.
  También entrega capacidad de misiles, selección de arma, cantidad de
  proyectiles y bombas activas, cuota/derrotas de la sala, dirección de estado y los ocho bytes
  originales de eventos y jefes. Estos campos son copias de lectura de la lógica;
  no conceden objetos ni disparan eventos.
  También expone energía máxima, índice de estación, slot de partida y un
  contador de escrituras SRAM completas, reiniciado al arrancar el núcleo.
  `beam_charge`, `charged_projectiles` y `time_frozen` copian el contador de
  carga, los proyectiles de rayo cargado activos y `time_is_frozen_flag`.
  Son diagnósticos de lectura; no cambian la lógica de disparo o las pausas.
  `get_enemies()` devuelve los slots vivos con ID, posición, salud, propiedades
  y AI. Es un diagnóstico opcional; no se copia en cada snapshot de dibujo.
  `get_snapshot()` añade los datos de dibujo al mismo estado.
- Los snapshots contienen estado, VRAM, CGRAM, OAM y un paquete `raster` con
  registros, paletas y límites de sprites para cada una de las 224 líneas.
  **No se expone un framebuffer como textura del juego.**
- `scripts/native_raster_renderer.gd` usa tres SubViewports: resuelve primero OAM
  mediante MultiMesh, luego main/subscreen con prioridades BG/OBJ por línea. El
  pass final aplica ventanas, color math, CGRAM y brillo. Mode 7 consulta tiles y
  matriz directamente en el shader. La variante mejorada aplica Scale2x sobre
  índices y luz/saturación moderadas. `raster_layout.md` documenta el paquete.

`prepare.py` genera una copia de `sm_rtl.c` para sustituir persistencia y convertir
el dispatch no soportado en un error. No altera el checkout de referencia ni la
ROM. La referencia C mantiene avisos de compilación y bugs conocidos por su autor;
la integración aún requiere comparación y correcciones.

## Evidencia y límites

La continuación desde Charge Beam ya comprueba tres saltos de pared originales,
regreso por el túnel de Morph Ball y movimiento de pie en Big Pink. Son 10503
ticks con 29 campos idénticos entre C y Godot; los últimos 431 ticks realizan
la salida sin cambiar salud, equipo, munición ni eventos. Ocho capturas suman
458752 píxeles RGB idénticos al oráculo offline. El ensayo recrea la SRAM de
Crateria desde controles normales y conserva los archivos fuente. Evidencia:
`docs/qa/native_pink_ascent_verification.json`. No verifica Spore Spawn ni
la campaña completa.

`godot_test.gd` verifica registro, propiedad única, 18000 ticks, llegada a Ceres,
movimiento, muestras de audio no silenciosas, tamaños de datos de dibujo y
descriptores de Mode 7, cierre/reinicio e integridad de ROM. La captura visual
comprueba sprites y fondo del ascensor inicial, con las dos variantes de arte.

El renderer ya lee cambios de registros por línea y recupera el HUD y el color
math de Ceres. Implementa ventanas, mosaico, offset-per-tile, límites de sprites,
prioridades, flips y OBJ interlace; estas variantes requieren ampliar las pruebas
de paridad. La rotación de OAM se ordena al principio del fotograma: cambios de
rotación dentro de un fotograma no se han implementado. VRAM y OAM se toman al
final del fotograma, por lo que cambios de esos datos durante líneas visibles
necesitan snapshots adicionales. La salida de modos 5/6 y pseudo hires conserva
256 píxeles horizontales; no reproduce la salida completa de 512 píxeles.
Tampoco se verificaron todos los enemigos, jefes, eventos, habitaciones, estaciones
y finales ejecutados por la referencia. La prueba no es una campaña completa,
una prueba de paridad por fotograma ni un reemplazo final del arte.

La comparación offline ejecuta la misma lógica C con el renderer de referencia
como oráculo, entrega sus paquetes al renderer de Godot y compara RGB sin
tolerancia. El oráculo no se usa en la escena de gameplay. Para reproducirla:

```sh
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release -DSM_BUILD_RENDER_ORACLE=ON
cmake --build native/build --target sm_raster_oracle --parallel 4
python3 tools/native_probe/verify_raster.py
```

La prueba actual compara cuatro fotogramas de la introducción, el ascensor de
Ceres (Mode 1 en el HUD y Mode 7 debajo) y el primer corredor tras bajar por las
plataformas con input normal. Los seis casos suman 344064 píxeles RGB idénticos;
no se omite un caso si el recorrido falla.

`docs/qa/native_raster_comparison.json` registra los fotogramas concretos,
discrepancias y alcance. Una captura idéntica demuestra esos píxeles y no la
campaña entera. El renderer anterior se conserva como referencia en
`scripts/native_renderer.gd`, pero la escena ya usa el renderer por línea.

También se verificó el recorrido completo de Ceres y la llegada a Landing Site:

```sh
cmake --build native/build --target sm_campaign_route sm_raster_oracle sm_native --parallel 4
python3 tools/native_probe/verify_campaign.py
/Applications/Godot.app/Contents/MacOS/Godot --path . --script tools/native_probe/campaign_menu_test.gd -- --native-core-ui-test
```

El controlador de prueba envía botones normales: baja por las seis salas, activa
a Ridley, recibe daño hasta la retirada original por salud baja, espera su
secuencia, vuelve por las plataformas antes del límite y permite que la nave
aterrice. Al final Samus camina en Landing Site. No cambia RAM, posiciones,
equipo, salud ni eventos; no entra en la extensión de gameplay.

Se registran 16836 inputs/estados y se reproducen en Godot, comparando estado,
sala, posición, pose, salud y evento/timer en cada tick contra el ejecutable C.
Cuatro capturas concretas de jefe, retirada, timer y llegada coinciden en sus
229376 píxeles RGB con el oráculo offline. La variante mejorada se captura a 2×.
`docs/qa/native_campaign_verification.json` conserva esa evidencia. La comparación
de estados prueba la integración con la referencia C; no es una comparación de
la CPU SNES ni verifica todos los desenlaces del combate o la campaña completa.

El recorrido posterior hasta Morph Ball también se puede reproducir:

```sh
cmake --build native/build --target sm_zebes_route sm_raster_oracle sm_native --parallel 4
python3 tools/native_probe/verify_zebes.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/native_probe/native_input_test.gd
```

`zebes_route.h` continúa la ruta de Ceres por Landing Site, Parlor, Climb, Pit,
el ascensor a Brinstar y Morph Ball. Dispara a las puertas y salta sobre las
plataformas; pulsa los controles originales del ascensor, recoge el PLM, cierra
su mensaje y transforma a Samus para rodar. Son 21959 ticks desde SRAM vacía;
ninguna acción escribe posición, inventario, eventos o salud. Las máscaras de
aire de `zebes_descent.h` proceden de la geometría extraída y sólo guían ese
controlador de pruebas, que no se enlaza con el juego.

Godot reproduce el input y compara todos los ticks con el ejecutable C, incluido
el inventario y el tipo de movimiento. Se comparan cuatro capturas concretas de
Parlor, Climb, Brinstar y Morph Ball con el oráculo offline. El alcance y los
resultados están en `docs/qa/native_zebes_verification.json`; esto no prueba los
primeros misiles, bombas, el despertar de Zebes, el resto de la campaña o la
equivalencia de lógica con la CPU SNES.

La comprobación de los primeros misiles continúa esa partida desde el comienzo:

```sh
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release -DSM_BUILD_RENDER_ORACLE=ON
cmake --build native/build --target sm_missile_route sm_raster_oracle sm_native --parallel 4
python3 tools/native_probe/verify_missiles.py
```

Son 23436 ticks hasta Construction Zone y First Missile. El controlador dispara
al bloque del pasaje, pasa como Morph Ball, rompe los pisos con el cañón y cruza
el segundo pasaje bajo. Recoge el tanque de la estatua original, conserva su
mensaje, selecciona misiles, dispara uno, verifica capacidad 5/munición 4,
cancela la selección y recupera movimiento. No cambia equipo ni memoria de juego.
Godot coincide por tick con el ejecutable C en inventario, selección, proyectiles
y eventos, además del estado y movimiento de Samus. Cuatro checkpoints, incluido
el mensaje por HDMA, coinciden en 229376 píxeles RGB con el oráculo offline.
`docs/qa/native_missile_verification.json` registra ese alcance; no prueba el
resto de mejoras, combate, estaciones o campaña.

El regreso a Crateria y el despertar de Zebes se comprueban con:

```sh
cmake --build native/build --target sm_awaken_route sm_raster_oracle sm_native --parallel 4
python3 tools/native_probe/verify_awaken.py
```

La ruta suma 26570 ticks desde el comienzo. Sube por Construction Zone, vuelve
al ascensor y entra en Pit, cuyo selector original elige el estado $9787 al
tener Morph Ball y misiles. Combate con los cuatro piratas de suelo y el de pared;
Zebes conserva el evento 0 apagado hasta completar la cuota de cinco derrotas.
El controlador sólo pulsa el mando, recoge los drops originales y consulta
enemigos vivos para apuntar al último pirata. No cambia salud, inventario, AI
ni eventos. Godot coincide por tick con el ejecutable C, incluido el estado de
sala, cuota y evento. Cuatro capturas de subida, regreso, combate y activación
coinciden en 229376 píxeles RGB con el oráculo offline.
`docs/qa/native_awaken_verification.json` conserva esa evidencia. La salida de
Pit y las bombas se amplían en la prueba siguiente; los demás jefes y el resto
de la campaña siguen por verificar.

El recorrido de bombas y Bomb Torizo se comprueba con:

```sh
cmake --build native/build --target sm_bomb_route sm_raster_oracle sm_native --parallel 4
python3 tools/native_probe/verify_bombs.py
```

Son 68964 ticks desde una partida nueva: regresa por Climb y Parlor despiertos,
cruza el pasaje de Morph Ball y combate en Flyway. El controlador vuelve a entrar
en Flyway para recuperar energía con drops originales; abre la puerta roja con
cinco pulsaciones de misil y recoge las bombas de la estatua. Después reduce la
salud original de Bomb Torizo de 800 a cero y espera el evento de derrota del
jefe. Coloca una bomba desde Morph Ball, espera su explosión y el regreso a una
pose de pie. No concede salud, munición, equipo ni eventos.

El ensayo reproduce primero `tools/native_probe/fixtures/bomb_prefix.inputs`:
33156 máscaras de mando registradas desde el arranque hasta la primera entrada
en Flyway. Se valida su hash y el de la ROM y se ejecuta cada tick; no es una
partida guardada ni un volcado de memoria. `--plan-from-start` permite recalcular
ese tramo con el controlador POSIX; ese modo de planificación completo no forma
parte de la evidencia publicada. Los procesos hijos de planificación sólo
proponen botones; no alteran el estado vivo ni entran al binario del juego.

Godot coincide con el registro C en todos los ticks, incluyendo bombas activas,
inventario, salud, puertas/salas, cuotas y bits de evento/jefe. Siete capturas de
Climb, pasaje, puerta roja, mensaje, combate, bomba y derrota suman 401408
píxeles RGB idénticos al oráculo offline. Hay audio no silencioso y la ROM
permanece intacta. `docs/qa/native_bomb_verification.json` conserva esta
evidencia. No prueba todos los desenlaces del combate, la salida de la puerta
gris, estaciones, mejoras posteriores ni la campaña completa.

El recorrido posterior de tanque de energía y estación se comprueba con:

```sh
cmake --build native/build --target sm_station_route sm_raster_oracle sm_native --parallel 4
python3 tools/native_probe/verify_station.py
```

Se reproducen 76436 ticks desde una partida nueva, incluyendo la salida gris
del jefe, los bloques de bombas de Parlor, el tanque de Terminator (energía
máxima 99 → 199) y el diálogo de Crateria Save. Los 23 campos del registro C
coinciden en Godot. La escritura original deja la estación en el índice 1 y
produce SRAM de 8192 bytes idéntica en ambos hosts.

Se cierra el núcleo, se vuelve a leer esa SRAM y se carga la partida mediante
los menús originales. Los 1247 ticks de recarga conservan sala, salud máxima y
actual, equipo, munición y bytes de eventos/jefes; el ensayo espera la animación
de entrada y demuestra movimiento. El oráculo de la recarga escribe solamente
en una copia privada de la SRAM de prueba. La prueba adicional de tamaño y
propiedad del archivo está en `native_station_seed_io.json`.

El prefijo `fixtures/station_prefix.inputs` contiene 75973 máscaras de mando
desde el arranque hasta la primera llegada a la estación. Su manifiesto valida
los hashes del input y la ROM. No contiene SRAM ni memoria del juego, y el
controlador continúa con botones normales. Esta evidencia cubre esa estación
y ese tanque; las demás estaciones, mejoras y rutas siguen pendientes.
Las seis capturas originales suman 344064 píxeles RGB idénticos al oráculo
offline; informe completo en `docs/qa/native_station_verification.json`.

Próximo trabajo: ampliar recorridos de combate, mejoras, otras estaciones, jefes y
final desde Landing Site, y sustituir
gradualmente el arte conservando anclajes y límites de cada animación.

El primer fondo nuevo también está integrado en esta escena: Landing Site usa
el arte de Crateria extraído como referencia para el fondo pintado de
`assets/remastered/crateria_backdrop.png`. Sólo reemplaza BG2 en gameplay y modo
mejorado; conserva una contribución del paisaje/lluvia original y el parallax
sigue la cámara. El HUD, terreno, sprites y ventanas conservan sus capas. F1
restaura el original; el mapa, menús y otras salas excluyen este fondo.

```sh
python3 tools/native_probe/verify_art.py
```

La prueba usa una SRAM propia, reproduce la ruta de Ceres, compara original y
restaurado con el oráculo, y exige cero diferencias fuera de BG2 respecto al
modo mejorado sin fondo. Su evidencia está en `docs/qa/native_art_verification.json`.

El fondo de pared de Ceres también está redibujado e integrado en las tres
salas que comparten la biblioteca `$8F:E4A5`: `$DF8D`, `$DFD7` y `$E06B`, tanto
antes de Ridley como durante el escape. `ceres_bg2_wall.png` procede de la
referencia BG2 decodificada de tiles/mapa/CGRAM; su JSON conserva el prompt de
ImageGen. Sólo reemplaza BG2 visible con índices 81–88. Sigue los registros de
scroll por línea y transfiere cambios CGRAM antes de ventanas, color math y
brillo. Las otras bibliotecas de Ceres, mapa, transiciones y Mode 7 mantienen
su composición. F1 devuelve el original.

```sh
cmake --build native/build --target sm_campaign_route sm_raster_oracle --parallel 4
python3 tools/native_probe/verify_ceres_art.py
python3 tools/native_probe/verify_art.py
```

El primer ensayo verifica 16836 ticks, tres salas y sus dos estados: seis
capturas originales/restauradas idénticas al oráculo y 1007964 píxeles de HUD,
terreno y sprites protegidos sin cambios. Además comprueba período/scroll de
BG2, CGRAM, fade/blanking y exclusiones. La segunda prueba vuelve a comprobar
Crateria. El alcance y las capturas están en `docs/qa/native_ceres_art_*`;
las demás familias de assets y la campaña completa siguen pendientes.

## Continuación hasta Brinstar verde

```sh
cmake --build native/build --target sm_station_route sm_green_route sm_raster_oracle --parallel 4
python3 tools/native_probe/verify_green.py
```

La prueba genera la SRAM original de Crateria Save desde el prefijo de botones
de partida nueva y comprueba que sus 8192 bytes coincidan con el guardado ya
verificado entre C y Godot. Cada host arranca con una copia privada de esa SRAM,
recorre los menús y espera la animación de carga. La continuación sube Parlor,
cruza su pared de bombas, pasa Terminator, baja Green Pirates Shaft, atraviesa
Lower Mushrooms y activa el ascensor original hasta Green Brinstar Main Shaft.
Se comprueba movimiento al llegar, con Morph Ball, bombas, tanque de energía,
misiles y los bytes de evento/jefe conservados.

Son 5316 ticks de partida recargada, 25 campos idénticos por tick entre C y
Godot y siete capturas originales con 401408 píxeles RGB idénticos al oráculo
offline. La SRAM fuente y ROM permanecen intactas; hay audio no silencioso.
El controlador recibe daño normal y termina con 9 de energía sobre un máximo
de 199. No concede salud, equipo, munición, eventos ni posición. El recorrido
atraviesa el pozo de piratas; no prueba derrotarlos ni todas sus variantes de IA.

`green_route` es un ensayo opcional POSIX, fuera del binario del juego. Sus
planificadores proponen botones en procesos hijos y sus máscaras de geometría
son de lectura. La comprobación publicada usa `--seed` con SRAM original;
el modo alternativo `--prefix` todavía no forma parte de esta evidencia.
Los informes y capturas están en `docs/qa/native_green_*`. Spore Spawn, Kraid,
otras rutas y el final siguen sin verificar.
El redibujado de las demás familias sigue pendiente.

## Atlas mejorado de Brinstar verde

```sh
python3 tools/native_probe/verify_green_art.py
```

`green_bg2_tiles.png` redibuja los 66 tiles de la paleta BG2 7 presentes en
Green Brinstar Main Shaft (`9AD9/9AE6`). La extracción conserva las coordenadas
de su atlas 8×8; el shader consulta el mapa nativo en VRAM para elegir cada
pieza, incluyendo sus giros y scroll. Mantiene las animaciones de CGRAM,
ventanas, brillo/color math y las capas de HUD, terreno y sprites.

La prueba usa una SRAM original regenerada mediante botones y recorre los
menús hasta Brinstar. Reproduce todos los campos de la continuación C/Godot,
compara las variantes original/restaurada con el oráculo y comprueba píxeles
protegidos, varias alturas de cámara y fixtures de presentación. Un cálculo
independiente verifica el muestreo del atlas y sus giros, con tolerancia de
redondeo de dos niveles RGB; la comparación del original es sin tolerancia.
Los fixtures cambian sólo copias del paquete de dibujo. El prompt y hashes
están en `assets/remastered/green_bg2_tiles.json`; resultados en
`docs/qa/native_green_art_*`. Campaña y redibujado completos siguen pendientes.

Licencias: la referencia usa MIT (`docs/licenses/snesrev-sm.txt`); godot-cpp usa
MIT (`docs/licenses/godot-cpp.txt`). Los gráficos y audio vienen de la ROM local.

## Fondo mejorado de Big Pink

`pink_bg2_tiles.png` redibuja los 16 tiles originales del BG2 de Big Pink,
con referencia extraída de VRAM y CGRAM. El mapa nativo conserva los IDs,
giros, scroll por línea y paleta; el reemplazo se limita a `9D19/9D26` durante
gameplay. HUD, BG1 y sprites mantienen sus capas. F1 restaura el original.

`python3 tools/native_probe/verify_pink_art.py` regenera una SRAM original
mediante botones desde el arranque y la carga por los menús originales.
Reproduce 8241 ticks con 25 campos por tick idénticos C/Godot, hasta Big Pink
y movimiento dentro de esa sala. Sus seis capturas tienen 344064 píxeles
RGB originales/restaurados idénticos al oráculo; 638316 píxeles protegidos
quedan intactos. El cálculo independiente de 562644 muestras verifica IDs,
giros y cambios de CGRAM, con un nivel RGB de error máximo. La ROM y SRAM
fuente quedan intactas; las regresiones de Brinstar verde, Ceres y Crateria
pasan. El prompt está en `assets/remastered/pink_bg2_tiles.json` y la evidencia
en `docs/qa/native_pink_art_*`. Spore Spawn, mejoras posteriores y campaña
completa siguen pendientes.

## Charge Beam y misiles inferiores

```sh
cmake --build native/build --target sm_station_route sm_charge_route sm_native sm_raster_oracle --parallel 4
python3 tools/native_probe/verify_charge.py
```

El recorrido añade el tanque inferior de Big Pink, el paso de bombas, la
esfera de la estatua y Charge Beam. Conserva los avisos originales y prueba
carga y liberación de Fire desde una pose nativa de Samus. Son 10072 ticks
con 29 campos de estado idénticos entre C y Godot; la carga llega al umbral
original de 60 ticks y aparecen 17 ticks con un proyectil cargado activo.
No consume misiles: termina con cinco disponibles sobre una capacidad de
diez, equipo `1004`, rayo `1000`, energía 24/199 y eventos/jefes conservados.

Diez capturas originales tienen 573440 píxeles RGB idénticos al oráculo,
incluidos los avisos de recogida y el disparo. Presentarlas no altera el
estado del núcleo. La prueba regenera la SRAM de Crateria desde inputs de
partida nueva y mantiene la ROM/SRAM fuente intactas. La prueba de registro,
propiedad única, 18000 ticks, cierre y reinicio del núcleo también pasó con
los nuevos diagnósticos. Informes y capturas: `docs/qa/native_charge_*`.
Esto no verifica el tanque superior, Spore Spawn ni la campaña completa.

## Fondo rocoso de Parlor

```sh
cmake --build native/build --target sm_station_route sm_green_route sm_raster_oracle --parallel 4
python3 tools/native_probe/verify_parlor_art.py
```

`parlor_bg2_tiles.png` redibuja los 44 tiles de Crateria Rocks extraídos de
VRAM/CGRAM, en un atlas de ocho columnas y seis filas. El shader sigue el
mapa nativo, giros, scroll y paleta por línea; protege HUD, BG1 y sprites.
Se aplica a Parlor `92FD` en los estados originales `9314` y `932E`. El estado
del escape final `9348` y otras salas con esta biblioteca quedan pendientes.

Los atlas de Brinstar verde, Big Pink y Parlor comparten un único sampler;
Godot enlaza sólo la textura de la familia activa. Así las familias nuevas
no añaden samplers para todas las texturas que no se usan en esa sala.

La prueba recorre el prefijo original de partida nueva hasta Parlor dormido
y una continuación desde la SRAM original de Crateria hasta Brinstar verde.
Comprueba siete capturas de cámara, las dos selecciones reales de estado,
25 campos por tick de la continuación, restauración original, píxeles
protegidos y muestreo independiente de los 44 IDs y los cuatro giros.
Los cambios de mapa/paleta/scroll del diagnóstico afectan sólo copias del
paquete de presentación. Resultados: `docs/qa/native_parlor_art_*`.
El prompt exacto está en `assets/remastered/parlor_bg2_tiles.prompt.txt`;
los hashes y dimensiones, en su JSON. Campaña y redibujado completos
siguen pendientes.
