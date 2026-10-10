# Prueba de la lógica compilada en C

Diagnóstico de la referencia MIT `snesrev/sm`, revisión fija
`578f90b3cc49557bb70060ad033bb90b8cf8ac50`. No reemplaza el proyecto Godot y
no representa una campaña completa. El código de referencia se declara temprano
y con bugs; la compilación conserva avisos del compilador en el log.

```sh
sh tools/native_probe/setup.sh
python3 tools/native_probe/build.py
python3 tools/native_probe/run.py
```

El build actual requiere clang y el linker de macOS. Compila las rutinas C del
juego y de su reproductor de audio, sin SDL, OpenGL ni la aplicación de referencia.
Conserva la infraestructura de memoria, registros, DMA, PPU y DSP del proyecto de
referencia para permitir ejecutar sus rutinas. **No es todavía una integración
de GDExtension ni un renderer nativo de assets en Godot.**

En copias generadas de `cpu.c` y `spc.c`, los dos puntos de entrada de ejecución
de opcodes abortan con `FORBIDDEN_OPCODE_EXECUTION`. El runner llama a
`RunOneFrameOfGame`, configura `RM_MINE` y reproduce audio con `SpcPlayer`.
Cualquier fallback a la CPU 65816 o al SPC emulado detendría la prueba. El fallback
`Call` de Bang sigue presente en la referencia: este recorrido no llega a ese
enemigo y no demuestra que todos los caminos estén portados a C.

Se simulan pulsaciones de Start/A para recorrer los menús y la introducción; al
entrar en el estado 8 se alterna dirección, salto y disparo. La prueba exige al
menos 300 cuadros de gameplay, llegada a la primera sala de Ceres (`$8F:DF45`),
movimiento horizontal, proyectiles y audio no silencioso. No comprueba puertas,
Ridley, escape de Ceres, otros jefes, recogida de mejoras, Tourian o final.

El runner crea SRAM en un directorio temporal independiente, comprueba SHA-256
antes y después, requiere el marcador `NATIVE_PROBE_OK` y guarda la evidencia en
`docs/qa/native_probe.log` y `native_probe.json`. La ROM y el checkout de referencia
no se modifican. Los parches de la referencia afectan a su copia de ROM en RAM.

Este diagnóstico se conserva como comprobación de arranque. La integración
posterior en `native/` ya separa el host, excluye los intérpretes de CPU/SPC,
resuelve el dispatch de Bang y expone paquetes de dibujo para los shaders de
Godot. `native/README.md` documenta el estado actual y sus límites.

`raster_oracle.c`, `raster_test.gd` y `verify_raster.py` forman la comprobación
offline del renderer por línea: introducción, ascensor y primer corredor de
Ceres. El oráculo produce los píxeles esperados sólo durante esa comprobación;
la escena del juego compone los paquetes VRAM/OAM/registros en Godot.

`campaign_route.c` y `ceres_route.h` añaden un controlador de prueba que sólo
envía botones normales y registra input/estado de Ceres hasta Landing Site.
`campaign_test.gd` reproduce ese registro mediante `SmNativeCore`; la comparación
por tick y las cuatro capturas se automatizan con `verify_campaign.py`. El oráculo
acepta opcionalmente el input registrado y una lista de checkpoints para dibujar
sólo esos fotogramas. La prueba de navegación del menú usa
`campaign_menu_test.gd -- --native-core-ui-test` y no toca la SRAM normal.

Licencia del código de referencia: `docs/licenses/snesrev-sm.txt`.

## Recorrido hasta bombas y Bomb Torizo

`bomb_route.c` y `bomb_route.h` prolongan el recorrido de despertar de Zebes.
El ensayo verificado vuelve por Climb y Parlor, cruza el pasaje de Morph Ball,
recupera energía en Flyway (`$8F:9879`), abre la puerta roja con cinco misiles,
recoge las bombas y derrota a Bomb Torizo. Coloca una bomba, espera su explosión
y recupera una pose de pie. `bomb_test.gd` reproduce los 68964 ticks en Godot con
paridad de estado; `verify_bombs.py` compara siete capturas originales sin
diferencias RGB. No prueba todavía estaciones, mejoras posteriores ni el final.
El ejecutable comunica `BOMB_ROUTE_INCOMPLETE` y devuelve 1 cuando no logra
todas sus condiciones; compilarlo no demuestra que pase.

El target es opcional, queda fuera de la compilación normal y requiere POSIX
(macOS/Linux). `route_lookahead.h` prueba saltos con pulsaciones normales en
procesos hijos, recibe sólo secuencias de botones y comprueba que el estado del
proceso principal no cambió. `parlor_return.h` contiene máscaras de geometría
de sólo lectura. Estas herramientas no se incorporan al juego.

Después de preparar `native/`, la comprobación completa usa:

```sh
cmake --build native/build --target sm_bomb_route sm_native sm_raster_oracle --parallel 4
python3 tools/native_probe/verify_bombs.py
```

Por defecto reproduce desde el arranque los 33156 botones registrados de
`fixtures/bomb_prefix.inputs`, validados con `bomb_prefix.json`, y continúa el
controlador desde Flyway. El prefijo no contiene ROM, SRAM ni memoria del juego.
También se puede ejecutar sólo el controlador con una carpeta temporal nueva:

```sh
route_output=$(mktemp -d)
native/build/sm_bomb_route '/ruta/a/Super Metroid.sfc' "$route_output" tools/native_probe/fixtures/bomb_prefix.inputs
```

La carpeta guarda `bomb.inputs` y `bomb.csv` para diagnosticar el recorrido.
Usa exclusivamente SRAM temporal; no reutilices una carpeta con una partida
que quieras conservar.
Omitir el prefijo, o usar `verify_bombs.py --plan-from-start`, recalcula también
la ruta inicial con los procesos hijos; ese modo completo de planificación no
forma parte del resultado verificado publicado.

## Tanque de energía, estación y recarga

```sh
cmake --build native/build --target sm_station_route sm_native sm_raster_oracle --parallel 4
python3 tools/native_probe/verify_station.py
```

La prueba reproduce desde una partida nueva los botones de
`fixtures/station_prefix.inputs`, comprobados con su manifiesto. Continúa hasta
guardar en Crateria Save con el diálogo original. El prefijo incluye la salida
gris de Bomb Torizo, los bloques de bombas de Parlor y el tanque de Terminator;
es una secuencia de botones, sin SRAM ni memoria del juego.

`station_test.gd` compara 23 campos por tick con el registro C, exige SRAM de
8192 bytes idéntica, cierra el núcleo y arranca con esa partida. Comprueba sala,
energía, equipo, munición, eventos y jefes, espera la animación de entrada de la
estación y prueba movimiento con botones normales. Compara seis capturas RGB
con el oráculo offline; para la recarga, éste usa una copia privada de la SRAM
de prueba y conserva el archivo fuente. También rechaza semillas de tamaño
incorrecto. Los resultados quedan en `docs/qa/native_station_*`; un fallo o
un marcador ausente impide considerar completa la comprobación.

El guardado de la prueba es independiente de la partida del jugador. Estos
controladores y procesos hijos permanecen fuera del binario del juego.

## Fondo redibujado de Ceres

`extract_ceres_bg2.py` decodifica el BG2 original desde tiles planares, mapa y
CGRAM del fixture `ceres_corridor` del oráculo; no usa sus píxeles renderizados.
Guarda PNG y manifiesto de referencia. ImageGen editó esa referencia para el
asset `ceres_bg2_wall.png`, con su prompt y hashes en el JSON contiguo.

```sh
cmake --build native/build --target sm_campaign_route sm_raster_oracle --parallel 4
python3 tools/native_probe/verify_ceres_art.py
```

El ensayo recorre una partida nueva de Ceres a Landing Site, compara input y
estado por tick y captura las tres salas que comparten ese BG2 antes y durante
el escape. Compara original/restaurado con el oráculo y exige que sólo cambien
píxeles de fondo elegibles. Los fixtures adicionales sólo cambian copias del
paquete de presentación, para comprobar scroll, CGRAM, fundidos y exclusiones;
no escriben memoria del juego. La regresión del fondo de Crateria se ejecuta
con `verify_art.py`. Los informes mantienen campaña y redibujado completos
como pendientes.
