# Paquete de dibujo por línea

`get_snapshot().raster` contiene 262144 bytes: textura R8 de 1024 × 256.
Las filas 0–223 describen las líneas visibles; 224–255 son relleno. El host captura
registros a H=512 antes del punto de dibujo, después del HDMA de la línea anterior
y de los cambios de IRQ. Los valores de 16 bits se almacenan little endian.

| Offset por fila | Contenido |
| --- | --- |
| 0–3 | Modo, prioridad BG3, brillo (0–15), forced blank |
| 4 | Flags Mode 7: flip X/Y, large field, char fill, extended BG |
| 5–7 | Tamaño de mosaico, máscara BG, línea inicial del mosaico |
| 8–11 | Máscaras de capas de main/sub y ventanas de main/sub |
| 12–15 | Límites izquierdo/derecho de ventanas 1 y 2 |
| 16–31 | Matriz Mode 7: A, B, C, D, centro X/Y, scroll X/Y |
| 32–63 | Cuatro bloques BG de 8 bytes: mapa, tiles, scroll X/Y |
| 64–67 | Flags BG: mapa ancho, alto, tiles grandes |
| 68–73 | Flags de las seis ventanas: inversa 1, activa 1, inversa 2, activa 2 |
| 74–79 | Lógica de combinación de ventanas: OR, AND, XOR, XNOR |
| 80–81 | Modo de recorte a negro y de prevención de color math |
| 82 | Flags: add subscreen, subtract, half, direct color, pseudo hires, interlace, even frame |
| 83 | Máscara de capas con color math |
| 84–86 | Color fijo R/G/B de 5 bits |
| 87 | Selector de tamaño de sprites |
| 88–91 | Dos direcciones base OBJ de 16 bits |
| 92–93 | Primera entrada OAM de la rotación de prioridad; OBJ interlace |
| 96–103 | Rango de prioridad BG bajo/alto; 255 significa ausente |
| 104–107 | Rango de las cuatro prioridades OBJ |
| 108–111 | Profundidad BG: 0 ausente, 2/4/8 bits, 7 para extended BG de Mode 7 |
| 128–255 | Máscara de columnas de 8 px permitidas para cada sprite, tras límites de 32 sprites/34 slivers |
| 256–767 | Copia de 512 bytes de CGRAM |

Las direcciones de VRAM del paquete se expresan en palabras. Los shaders las
convierten a bytes para consultar `snapshot.vram`, una textura R8 de 256 × 256.
OAM contiene sus 512 bytes principales seguidos de los 32 bytes de high OAM.

Godot resuelve primero el primer píxel opaco según OAM, luego las prioridades de
BG y OBJ de cada pantalla, y finalmente ventanas, color math y brillo. Los passes
intermedios guardan índices y etiquetas de capa en RGBA8, sin convertirlos a sRGB.
El pass final consulta CGRAM por línea. Las mallas usan UV con origen superior
izquierdo explícito para conservar la orientación de los tiles en canvas.
Ninguna textura del juego contiene una
imagen renderizada por la PPU de referencia.

`sm_raster_oracle` es una herramienta offline opcional de QA. Activa el renderer
de referencia sobre la misma lógica C para producir la imagen esperada; no se
enlaza ni se ejecuta como parte de la escena Godot. La prueba actual demuestra
paridad de capturas concretas de la introducción y Ceres, no de todos los modos
ni de la campaña. Los resultados medidos están en `docs/qa/native_raster_comparison.json`.
