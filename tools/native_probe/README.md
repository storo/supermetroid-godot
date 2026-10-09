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

Próximo trabajo: separar el host y la dependencia de CPU del núcleo, resolver
dispatch faltante, exponer estado y datos de dibujo mediante GDExtension y dibujar
los tiles/sprites con sus reemplazos mejorados en Godot. Conservar este diagnóstico
como comprobación de arranque y ampliar las pruebas a recorridos completos.

Licencia del código de referencia: `docs/licenses/snesrev-sm.txt`.
