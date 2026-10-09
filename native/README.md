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

La escena independiente conserva los menús y la introducción ejecutados por el
núcleo. Enter envía Start; espacio/Z envía A; J/X envía X; Shift envía B; K envía
Select para elegir misiles; Q/E envían R/L. A/D o flechas y W/S controlan la cruz.
F1 alterna arte; Escape congela la prueba. Las acciones de Morph Ball y bombas
siguen los botones originales del núcleo (Down y X). No hay equipo concedido por
la escena. La SRAM usa `user://native_campaign.srm` y no sustituye el JSON de la
escena principal. El `--native-core-capture` usa SRAM de prueba independiente,
recorre la introducción mediante input y captura el ascensor inicial de Ceres.

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
- Los snapshots contienen estado, VRAM, CGRAM, OAM y parámetros de capas/Mode 7.
  **No se expone un framebuffer como textura del juego.**
- `scripts/native_renderer.gd` compone tiles y sprites mediante MultiMesh de
  Godot, conservando posiciones, tamaños y flips. Mode 7 se dibuja con una malla
  y un shader que consulta sus tiles, paleta y matriz. Los shaders aplican Scale2x
  y luz/saturación moderadas sobre los datos gráficos originales.

`prepare.py` genera una copia de `sm_rtl.c` para sustituir persistencia y convertir
el dispatch no soportado en un error. No altera el checkout de referencia ni la
ROM. La referencia C mantiene avisos de compilación y bugs conocidos por su autor;
la integración aún requiere comparación y correcciones.

## Evidencia y límites

`godot_test.gd` verifica registro, propiedad única, 18000 ticks, llegada a Ceres,
movimiento, muestras de audio no silenciosas, tamaños de datos de dibujo y
descriptores de Mode 7, cierre/reinicio e integridad de ROM. La captura visual
comprueba sprites y fondo del ascensor inicial, con las dos variantes de arte.

El renderer aún no reproduce cambios de registros por línea, ventanas, color math,
mosaico, offset-per-tile, modos 5/6, límites de sprites y todas las variantes de
Mode 7. El HUD de Ceres y algunas escenas requieren esos cambios por línea.
Tampoco se verificaron todos los enemigos, jefes, eventos, habitaciones, estaciones
y finales ejecutados por la referencia. La prueba no es una campaña completa,
una prueba de paridad por fotograma ni un reemplazo final del arte.

Próximo trabajo: capturar los parámetros de dibujo por línea y reproducirlos en
los shaders de Godot; verificar el recorrido de Ceres, escape y Landing Site;
después ampliar recorridos de combate, mejoras, estaciones, jefes y final.

La captura de registros por línea ya se expone en el campo `raster` del snapshot.
Los archivos `shaders/raster_*` contienen el siguiente renderer en desarrollo;
todavía no están conectados a la escena ni se ha validado su resultado. La escena
sigue usando `scripts/native_renderer.gd` y conserva los límites indicados arriba.

Licencias: la referencia usa MIT (`docs/licenses/snesrev-sm.txt`); godot-cpp usa
MIT (`docs/licenses/godot-cpp.txt`). Los gráficos y audio vienen de la ROM local.
