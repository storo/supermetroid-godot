# Super Metroid — reconstrucción nativa en Godot

Proyecto en desarrollo basado en la ROM local de SNES. El movimiento, las colisiones, los proyectiles y las salas se ejecutan en Godot; no hay emulador. El objetivo sigue siendo conservar el juego completo y mejorar sus assets. **Todavía no es un remake completo; la campaña entera sigue sin verificar.**

## Ejecutar

El repositorio incluye el proyecto, los assets extraídos/mejorados y las herramientas.
La ROM, las partidas, las cachés y los binarios de compilación se mantienen fuera
del repositorio. La integración opcional de `native/` requiere la ROM local y
compilar su extensión siguiendo `native/README.md`.

Abre `project.godot` con Godot 4.5 o posterior y pulsa F5, o haz doble clic en `Iniciar.command` en este Mac. Fue probado con Godot 4.7.1.

En el menú puedes empezar en Landing Site o usar **Explorar salas**. El visor habilita equipo básico para revisar los escenarios sin confundirlo con la progresión de una partida nueva.

Con la ROM local y la extensión compilada (`sh native/setup.sh`), el menú también
ofrece **Jugar desde Ceres**. Esa escena conserva la introducción, Ridley, el escape
y la llegada a Zebes de las rutinas C originales. También se verificó el recorrido
Landing Site → Parlor → Climb → Pit → ascensor → Morph Ball → Construction Zone
→ primeros misiles → regreso a Crateria → cinco piratas de Pit → Climb → Parlor
→ pasaje de Morph Ball → Flyway → bombas y derrota de Bomb Torizo
→ tanque de Terminator → estación de guardado de Crateria.
La recogida, transformación, disparo, consumo de munición y despertar de Zebes
se comprueban con controles normales. La nueva prueba también abre la puerta roja
con cinco misiles, recupera salud con drops originales, coloca una bomba y espera
su explosión y la vuelta al control de Samus. F10 vuelve al menú. Su partida
SRAM es independiente del guardado JSON de la reconstrucción GDScript.
La extensión lee esa SRAM al arrancar y permite continuar desde la estación
mediante los menús originales.

En esa campaña nativa, S/↓ agacha y transforma a Samus después de conseguir Morph
Ball; J/X dispara o coloca bombas cuando se dispone de ellas. Enter envía Start
para el menú/mapa original, K envía Select y Retroceso cancela el arma elegida.
El mando usa A para saltar, B para correr, X para disparar, Y para cancelar,
Start/Back para Start/Select y R/L para apuntar. La cruz y el stick izquierdo
controlan el movimiento. Escape congela la aplicación.

En Landing Site, el modo mejorado integra el fondo nuevo de Crateria con
parallax de cámara. Se aplica sólo a la capa lejana BG2 durante el gameplay;
el HUD, Samus, la nave y el terreno conservan su composición nativa. F1 recupera
el dibujo original. El mapa y las demás salas no reciben este fondo.

Tres salas de Ceres también usan un fondo redibujado a partir de sus tiles y
paleta: el corredor del ascensor, la escalera y el corredor previo a Ridley.
Conserva la distribución de los seis módulos de la pared, con metal y luces de
mayor detalle. Sigue el desplazamiento original de BG2 y los cambios de paleta,
incluido el escape; HUD, terreno y sprites mantienen sus capas. F1 restaura el
original en el mismo estado de juego.

El pozo principal de Brinstar verde también usa sus 66 tiles BG2 redibujados
con ImageGen. Conserva los índices, posiciones y giros de cada pieza en el mapa
nativo, además de las animaciones de paleta. Se aplica a esa sala/estado;
F1 recupera el original y las capas del HUD, terreno y sprites se conservan.

| Acción | Tecla |
| --- | --- |
| Mover | A/D o flechas |
| Saltar / salto en pared | Espacio o Z |
| Disparar | J o X |
| Misiles | K |
| Correr | Shift |
| Apuntar arriba / diagonal arriba / diagonal abajo | W / Q / E |
| Agacharse | S |
| Morph Ball / bomba | C / B; requieren sus objetos |
| Activar ascensor desde su plataforma | S / ↓ para bajar; W / ↑ para subir |
| Mapa / pausa | Tab / Escape |
| Comparar assets originales y mejorados | F1 |
| Visor de salas | F4 |
| Guardar / cargar | F5 / F9 dentro del juego |
| Pantalla completa | F11 |

También hay bindings de mando. La partida se guarda en el directorio `user://` de Godot, separada de la ROM.

## Estado real

- 261 salas originales, 322 estados, geometría, BTS, puertas, poblaciones de enemigos y ubicaciones de PLM extraídas a JSON.
- 29 tilesets y 19 conjuntos de animación de Samus (nueve movimientos en ambos sentidos y la pose frontal del ascensor) reconstruidos desde tiles 4bpp, paletas, DMA y OAM de la ROM.
- Ampliación 4× con Scale2x por tile; conserva índices y límites. F1 permite la comparación directa.
- Gráficos dinámicos de 17 mejoras de PLM, con sus dos frames y las paletas de cada tileset; los cuatro tipos de tanque conservan sus tiles de CRE.
- Nave reconstruida con sus capas y desplazamientos originales; gráficos y parámetros de 154 tipos de enemigos extraídos. Zoomer, Ripper y Skree tienen implementación nativa aproximada. Los piratas grises de suelo y pared usan 55 frames compuestos, hitboxes y secuencias de la ROM; sus rutinas de movimiento y ataque están adaptadas a Godot.
- Movimiento, salto variable, pared, carrera, Morph Ball, bombas, disparos, recogida básica de objetos, transición entre salas, mapa y persistencia.
- Gravedad, impulso de salto, aceleración y velocidad de carrera leídos de las constantes de la ROM y convertidos a unidades por segundo.
- 61 condiciones de selección de estado leídas de la ROM: eventos, bits de jefe por área, Morph Ball con misiles y Power Bombs. Se evalúan en su orden original al entrar a una sala; los eventos y bits de jefe se guardan.
- Puertas grises con condiciones de jefe o cuota de enemigos. Derrotar a los cinco piratas de Pit despierta Zebes; recoger Morph Ball por sí solo no lo hace. Los láseres enemigos dañan a Samus y pueden destruirse con disparos.
- Los siete pares de ascensores usan posiciones y dirección de la población original, velocidad de 90 px/s, animación de dos cuadros, pose frontal de Samus y demora de 48 ticks antes de la transición descendente. Se puede volver desde Morph Ball. Los disparadores virtuales se conservan separados de las puertas completas.
- Fondo nuevo de Crateria creado a partir de la referencia extraída, lluvia, partículas, resplandor y viñeta discreta.
- Fondo de pared de Ceres redibujado con ImageGen a partir del mapa BG2 original; integrado en tres salas y sus estados de entrada/escape de la campaña nativa.
- Atlas de 66 tiles BG2 de Brinstar verde redibujados con ImageGen a partir de VRAM/CGRAM, integrado con los índices y giros originales en el pozo principal nativo.

Quedan por reconstruir los disparadores de la mayoría de eventos de la historia, jefes, mayoría de IA, secuencias de Ceres y final, música SPC, comportamiento completo de PLM, líquidos y arena, todas las mejoras y fidelidad exacta de la física y las animaciones. Las puertas verdes/amarillas necesitan sus armas; varias puertas grises dependen de enemigos o secuencias todavía pendientes. El visor de salas permite abrirlas para revisar el mapa.

El guardado rápido se habilita al terminar el viaje en ascensor, para conservar una posición desde la que se pueda continuar la partida.

Consulta `docs/FIDELITY.md` para los requisitos del juego completo, `docs/ART.md` para el origen del arte y `docs/qa/` para pruebas y capturas.

Hay además una integración independiente de las rutinas C de la lógica original
mediante GDExtension en `native/`. Se verificó el recorrido Ceres → Ridley → escape
→ llegada a Landing Site → Morph Ball → primeros misiles → despertar de Zebes
→ bombas y Bomb Torizo con control de Samus,
transformación, movimiento, disparos, consumo de munición y audio;
Godot compone sus tiles/sprites, cambios por línea, HUD, color math y fondo de
Mode 7 con shaders. Hay una prueba de comparación de píxeles contra un oráculo
offline; sus resultados y alcance están en `docs/qa/native_raster_comparison.json`.
Los intérpretes de CPU/SPC no se compilan. La integración sigue en desarrollo y
se puede abrir desde el menú, pero todavía no prueba la campaña completa. Consulta
`native/README.md` para ejecutarla y revisar sus límites.

La comprobación de bombas usa `python3 tools/native_probe/verify_bombs.py`: 68964
ticks desde una partida nueva, estado idéntico entre C y Godot y siete capturas
originales comparadas sin diferencias RGB. Requiere compilar los targets
`sm_bomb_route`, `sm_raster_oracle` y `sm_native`. No verifica todavía los demás
jefes, estaciones ni el final.

La prueba `python3 tools/native_probe/verify_station.py` amplía el recorrido a
76436 ticks desde una partida nueva: salida gris del jefe, bloques de bombas,
primer tanque de energía y guardado en Crateria. Compara 23 campos por tick y
exige SRAM de 8192 bytes idéntica entre C y Godot. Cierra y abre el núcleo,
recorre 1247 ticks de carga y comprueba sala, energía, equipo, munición,
eventos, jefes y movimiento. Sus seis capturas originales suman 344064 píxeles
RGB idénticos al oráculo offline. Requiere los targets `sm_station_route`,
`sm_raster_oracle` y `sm_native`; evidencia en `docs/qa/native_station_*`.
El resto de estaciones, mejoras, jefes y final siguen sin verificar.

La continuación desde esa partida hasta Brinstar verde también se comprobó:
menús y recarga original → subida de Parlor y bloques de bombas → Terminator
→ pozo de piratas verdes → Lower Mushrooms → ascensor → control en el pozo
principal de Brinstar. `python3 tools/native_probe/verify_green.py` genera la
SRAM mediante botones desde una partida nueva, la carga por los menús originales
y reproduce 5316 ticks en Godot. Sus 25 campos de estado coinciden con C y siete
capturas suman 401408 píxeles RGB idénticos al oráculo. Conserva el equipo y los
eventos guardados; la ROM y SRAM fuente permanecen intactas. Es un recorrido
concreto de continuación, con daño real (termina con 9 de energía), y cubre
el viaje en ascensor y movimiento al llegar. Spore Spawn, Kraid y el resto de
la progresión siguen pendientes.

`python3 tools/native_probe/verify_green_art.py` comprueba los tiles BG2
redibujados de Brinstar en esa continuación. Nueve capturas originales y
restauradas suman 516096 píxeles RGB idénticos al oráculo; 1830828 píxeles
protegidos mantienen HUD, terreno y sprites. Un cálculo independiente comprueba
433838 muestras del atlas, incluidos cambios de IDs, giros y CGRAM, con error
máximo de un nivel RGB. También verifica scroll, exclusiones, fade y blanking.
La ROM/SRAM fuente permanecen intactas; campaña y redibujado completos siguen
pendientes. Evidencia: `docs/qa/native_green_art_verification.json`.

`python3 tools/native_probe/verify_ceres_art.py` verifica el fondo nuevo durante
16836 ticks desde una partida nueva: seis capturas con original/restaurado
idénticos al oráculo y 1007964 píxeles protegidos sin cambios. Comprueba scroll,
paleta, fundidos y exclusión de mapa, otras bibliotecas y ascensor Mode 7.
La comprobación de Crateria (`verify_art.py`) también sigue pasando. El
redibujado completo de las demás familias de assets sigue pendiente.

## Regenerar assets desde la ROM local

Python 3 con Pillow y NumPy (`python3 -m pip install -r tools/requirements.txt`). La extracción valida SHA-256 y nunca modifica la ROM.

```sh
./tools/setup_reference.sh
python3 tools/extract_rom.py
python3 tools/extract_objects.py
```

Se admite la versión NTSC Japan/USA con SHA-256 `12b77c4bc9c1832cee8881244659065ee1d84c70c3d29e6eaf92e6798cc2ca72`; se reconoce también un encabezado de copiador de 512 bytes. `extract_rom.py --rom /ruta/a/archivo.sfc` permite seleccionar la ROM.

## Verificar

```sh
python3 tools/verify_assets.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --smoke-test
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --room-audit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --progression-test
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --pirate-test
/Applications/Godot.app/Contents/MacOS/Godot --headless --max-fps 60 --path . --quit-after 2400 -- --elevator-test
/Applications/Godot.app/Contents/MacOS/Godot --headless --max-fps 60 --path . --quit-after 120 -- --elevator-morph-test
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --capture
```

Las pruebas básicas verifican movimiento, salto, proyectil, Morph Ball, cambio de sala, alternancia de arte y guardado/carga. La auditoría instancia cada sala y estado con colisiones nativas y comprueba un punto de aparición libre. La prueba de progresión verifica los 261 estados por defecto, las 61 condiciones, prioridad, cuotas y persistencia. La prueba de piratas ejecuta sus ataques, comprueba daño y destrucción de láseres, mata a los cinco con proyectiles nativos y verifica puertas y cambio de estado. Estas pruebas **no demuestran equivalencia con el juego completo**.

La prueba de ascensores recorre Crateria ↔ Brinstar con teclado y física del motor; comprueba pausa, bloqueo temporal de controles, retorno desde Morph Ball, comparación de arte y guardado al llegar. Los 14 trayectos se recorren además con pasos nativos deterministas. El caso de Morph Ball comprueba que el contacto con el piso permita ponerse de pie y que un techo real lo impida. Los procesos acotados deben imprimir su marcador `*_OK`; un código de salida 0 por alcanzar `--quit-after` no prueba que la verificación haya terminado.

La prueba adicional `sm_pink_route` continúa hasta Big Pink: cinco piratas
verdes, sus drops de munición, puerta roja y barrera de bombas de Dachora.
`tools/native_probe/pink_test.gd` reproduce el registro con 25 campos por tick
en Godot; el alcance está documentado en `tools/native_probe/README.md`.
Spore Spawn y la campaña completa siguen pendientes.
