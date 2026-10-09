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
la escena. La SRAM usa `user://native_campaign.srm` y no sustituye el JSON de la
escena principal. El `--native-core-capture` usa SRAM de prueba independiente,
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

Próximo trabajo: ampliar recorridos de combate, mejoras, estaciones, jefes y
final desde Landing Site, y sustituir
gradualmente el arte conservando anclajes y límites de cada animación.

Licencias: la referencia usa MIT (`docs/licenses/snesrev-sm.txt`); godot-cpp usa
MIT (`docs/licenses/godot-cpp.txt`). Los gráficos y audio vienen de la ROM local.
