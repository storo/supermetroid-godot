# Arte y trazabilidad

Los gráficos originales se decodifican de la ROM local identificada en `assets/extracted/manifest.json`. Los assets mejorados no sobrescriben los originales.

- `assets/extracted/tilesets/*_original.png`: metatiles de 16×16, atlas de 32×32 celdas, tiles SNES 4bpp y paletas originales.
- `*_enhanced.png`: metatiles de 64×64, cada celda ampliada independientemente con Scale2x dos veces. Se conserva su índice.
- `assets/extracted/samus/`: 19 conjuntos de animación (nueve movimientos en ambos sentidos y pose frontal del ascensor). Cada frame original ocupa 64×64 y usa el centro [32,32] como anclaje OAM.
- `assets/extracted/objects/elevator_*.png`: los dos cuadros de $A3:962F/9645, con tiles comunes de $9A:D200 y paleta de sprites 5; versiones original y 4×. `elevator.json` conserva la trazabilidad de sus constantes.
- `assets/extracted/objects/`: atlas de tiles de 154 encabezados de enemigo, nave ensamblada con offsets de inicialización de la ROM y cinco conjuntos de animación. Los piratas grises de suelo/pared suman 55 frames de spritemaps compuestos con offsets e hitboxes originales; los 11 frames de láser usan los tiles comunes y la paleta de sprites 5. Todos tienen variantes 4×.
- `assets/extracted/items/`: gráficos de 17 mejoras dinámicas, decodificados desde el banco $89; dos frames y variantes con las paletas de los 29 tilesets. Los tanques usan los metatiles CRE $4A–$51.
- `assets/remastered/crateria_backdrop.png`: fondo nuevo, destinado al proyecto, creado con la herramienta integrada ImageGen usando `assets/extracted/references/crateria_reference.png` como referencia de colores y terreno. No altera colisiones.
- `assets/extracted/references/ceres_bg2_original.png`: mapa original BG2 de 512×256, decodificado de VRAM 4bpp, mapa y CGRAM de Ceres. Su JSON conserva hashes, direcciones, índices y colores de paleta.
- `assets/remastered/ceres_bg2_wall.png`: redibujado de esa referencia con la herramienta integrada ImageGen, 1774×887. Su JSON guarda el prompt final, hashes y salas de destino; los originales se conservan.
- `assets/extracted/references/green_bg2_tiles_original.png`: atlas 128×64 de 66 tiles BG2 de Brinstar verde, decodificado de VRAM/CGRAM y conservando las coordenadas originales de cada tile 8×8. Su JSON registra índices, paleta, hashes y sala/estado.
- `assets/remastered/green_bg2_tiles.png`: redibujado de ese atlas con ImageGen integrado, 1774×887. El prompt completo, hashes y alcance están en el JSON del mismo nombre. Conserva los espacios negros del atlas y la ubicación de cada grupo; se aplica al BG2 de `9AD9/9AE6`.
- `assets/extracted/references/pink_bg2_tiles_original.png`: los 16 tiles BG2 de Big Pink, decodificados de VRAM/CGRAM y reunidos en una cuadrícula 4×4 de 32×32 píxeles. Cada celda mantiene su contenido original; su JSON registra los IDs, la paleta 3 y las coordenadas del atlas nativo.
- `assets/extracted/references/parlor_bg2_tiles_original.png`: 44 tiles de Crateria Rocks en Parlor, extraídos de VRAM/CGRAM. El atlas 64×48 conserva los grupos nativos de filas 12–15/columnas 8–15 y filas 30–31/columnas 10–15; su JSON registra cada ID, celda y paleta 4.
- `assets/remastered/pink_bg2_tiles.png`: edición de esa referencia con ImageGen integrado, 1254×1254. Redibuja el patrón orgánico azul oscuro; el JSON contiguo guarda el prompt completo y hashes. El compositor usa los IDs/giros de VRAM en `9D19/9D26` para ensamblar las mismas piezas, con la CGRAM y scroll actuales.

`shaders/asset_lighting.gdshader` añade relieve e iluminación de superficie a los sprites ampliados, derivando normales de su propia luminancia. No cambia UV, silueta, alpha ni anclajes. F1 también desactiva este material.

El generador de imágenes rechazó la solicitud de redibujar la hoja de Samus. Ese arte no se generó ni se usa en el proyecto. Las animaciones actuales son las extraídas y ampliadas.

## Prompt final del fondo

> Asset type: environmental parallax background texture for a 2D side-scrolling game. The reference is a terrain crop from the game's ROM. Create an atmospheric high resolution distant background behind this terrain, compatible with its dark teal, violet stone and moss green palette. Wide 1536x768 landscape, beautifully painted moody science fiction alien planet surface at night, rain clouds and distant layered craggy ridges, hints of ruined stone architecture far away, hazy cyan shafts of light, luminous green atmospheric motes, deep blue-black sky. Scene seen side-on from low ground level, distant ridges occupy bottom third, mostly open misty sky above, no foreground floor or solid collision objects, no characters, no spaceship, no text. Restrained contrast so the reference's brighter playable terrain and golden character remain visible. Polished modern 2D game environmental art, painterly precise rock texture, subtle cinematic volume, not photorealism, not pixel art. Preserve the supplied terrain's color mood but produce the separate distant scenery only.

## Referencias técnicas

Se leen nombres y direcciones de la [desensamblación anotada de Super Metroid](https://github.com/InsaneFirebat/sm_disassembly), revisión `7af131ebc328359e852e923603163a329c7aa7af`. La lógica nativa de Godot es código del proyecto; no ejecuta código 65816 de la ROM. El manifiesto y la matriz de fidelidad distinguen extracción de datos de implementación del juego.

Las rutinas de piratas de `scripts/pirate.gd` se adaptaron con referencia al banco $B2 y a `sm_b2.c` de [snesrev/sm](https://github.com/snesrev/sm), revisión `578f90b3cc49557bb70060ad033bb90b8cf8ac50`. Se conserva la atribución y licencia MIT en `docs/licenses/snesrev-sm.txt`. No se integra su emulador ni su ejecutable C.

`scripts/elevator.gd` adapta las rutinas del banco $A3 usando también `sm_a3.c` de esa misma revisión y licencia como referencia. Los sprites y constantes se decodifican de la ROM local.
# Renderizado del núcleo C en Godot

La escena independiente `scenes/native_campaign.tscn` recibe tiles/paletas/OAM
dinámicos de la ROM a través de `SmNativeCore`. No modifica las imágenes extraídas
ni usa una captura del juego como textura. Los shaders `raster_*.gdshader`
componen los gráficos, ventanas, paletas y color math por línea;
la variante mejorada aplica Scale2x,
luz y saturación moderadas. F1 permite comparar el mismo estado de Ceres. Las
capturas `native_ceres_original.png` y `native_ceres_enhanced.png` muestran el
ascensor inicial tras ejecutar la introducción original con input. La variante
original tiene paridad RGB en seis capturas concretas de introducción/Ceres,
registradas en `docs/qa/native_raster_comparison.json`. Queda ampliar la verificación
de efectos y escenarios; esto no sustituye el
redibujado completo de assets ni prueba la campaña.

El recorrido nativo Ceres → Ridley → escape → Landing Site añade cuatro capturas
comparadas sin tolerancia RGB en `native_campaign_verification.json`. Las versiones
`native_campaign_*_enhanced.png` se dibujan a 2× con Scale2x y luz/saturación; sus
anclajes, tiles y paletas provienen del mismo estado que las capturas originales.
Este tratamiento del arte sigue siendo una primera mejora, no su redibujado final.

La ruta de Zebes añade capturas de Parlor, Climb, Brinstar y Morph Ball en
`native_zebes_*_{original,enhanced,oracle}.png`. El renderer nativo produce la
variante mejorada a 2× con el mismo tratamiento; las versiones originales se
comparan sin tolerancia RGB en `native_zebes_verification.json`. No se añadieron
redibujados de personajes en esta ampliación.

`native_missile_*_{original,enhanced,oracle}.png` añade Construction Zone, el
mensaje del tanque y el disparo de misiles. La mejora a 2× mantiene el tratamiento
actual del renderer; cuatro capturas originales coinciden con el oráculo en
`native_missile_verification.json`, incluido el texto y HDMA del mensaje.

La prueba del despertar de Zebes agrega subida, regreso, combate y el evento
en `native_awaken_*_{original,enhanced,oracle}.png`. Las cuatro capturas originales
coinciden con la PPU offline; las versiones a 2× usan la mejora actual del shader.
No se añadieron redibujados en esta comprobación.

El recorrido de bombas y Bomb Torizo añade siete capturas en
`native_bomb_*_{original,enhanced,oracle}.png`: Climb despierto, el pasaje de
Morph Ball, la puerta roja, el mensaje de las bombas, combate, colocación de una
bomba y derrota del jefe. Sus 401408 píxeles originales coinciden con la PPU
offline en `native_bomb_verification.json`. Las variantes a 2× conservan el
tratamiento del shader; no se generaron redibujados nuevos para este recorrido.

## Fondo nuevo en la campaña nativa

El renderer nativo también usa `assets/remastered/crateria_backdrop.png` en
Landing Site ($91F8), durante el estado de gameplay 8 y con F1 en modo mejorado.
Se reutiliza el fondo creado con ImageGen y el prompt documentado arriba,
basado en la referencia extraída.

El compositor identifica los píxeles que pertenecen a BG2 en la pantalla
principal y los mezcla con el fondo nuevo (82% arte nuevo / 18% composición
original), conservando una contribución de la lluvia y paisaje animados. La
cámara desplaza la textura a un cuarto del movimiento horizontal; los límites
de imagen se sujetan sin repetición. Ventanas, color math y brillo por línea
también se aplican al arte nuevo. No se cambia VRAM, OAM ni la lógica C.

El HUD superior, BG1/terreno, sprites, bordes donde Scale2x cambia de capa y
blanking quedan protegidos. La luz de relieve se calcula del original antes de
mezclar el fondo, para que el arte nuevo no cambie la iluminación de Samus o la
nave. El mapa, menús, transiciones y salas distintas de Landing Site excluyen
este reemplazo. F1 desactiva tanto el fondo como las mejoras y recupera el
original.

`python3 tools/native_probe/verify_art.py` reproduce Ceres y la llegada a Zebes,
compara el modo original/restaurado contra la PPU offline y compara las capas
protegidas contra el modo mejorado sin fondo. También comprueba el parallax,
la exclusión por sala/estado, el fundido a brillo cero, el blanking forzado y
que presentar las variantes no altera el núcleo.
Capturas e informe: `docs/qa/native_art_*`. El alcance es este fondo de Landing
Site; no implica que los demás assets estén redibujados ni la campaña completa.

El recorrido de Terminator y Crateria Save añade seis grupos de capturas
`native_station_*_{original,enhanced,oracle}.png`: salida gris, bloques de
bombas, tanque, entrada a la estación, partida guardada y partida recargada.
Los 344064 píxeles originales coinciden con el oráculo offline en
`native_station_verification.json`. Las variantes a 2× usan el filtro del
renderer sobre los assets originales de esas salas. El redibujado de esas
familias de assets sigue pendiente.

## Pared redibujada de Ceres

`ceres_bg2_wall.png` mejora la pared original de seis módulos azules, con domos,
cuellos, rejillas, conductos y paneles metálicos. Se generó como edición de
`ceres_bg2_original.png`; el prompt completo está en
`assets/remastered/ceres_bg2_wall.json`. No contiene personajes, HUD ni terreno
jugable. La referencia se puede regenerar con `extract_ceres_bg2.py` usando el
fixture `ceres_corridor` de `sm_raster_oracle`.

La biblioteca original `$8F:E4A5` se comparte en `$DF8D`, `$DFD7` y `$E06B`,
en sus estados anteriores y posteriores a la retirada de Ridley. El selector
exige sala, estado de sala y gameplay; los otros fondos de Ceres y el ascensor
Mode 7 quedan fuera. El compositor sustituye sólo píxeles visibles de BG2 con
sus índices originales 81–88, protegiendo HUD, BG1 y todos los sprites.

El nuevo dibujo repite el mapa lógico de 512×256 con los registros BG2 X/Y por
línea, conservando desplazamiento y sacudidas nativos. Transfiere la diferencia
entre CGRAM actual y la paleta de referencia de cinco bits al arte nuevo, antes
de ventanas, color math y brillo. Conserva la mezcla 82% nuevo / 18% original.
La iluminación de las otras capas se sigue calculando del original.

`verify_ceres_art.py` reproduce 16836 ticks desde el arranque hasta Landing Site.
Las seis capturas, tres salas y dos estados, tienen 344064 píxeles originales y
restaurados idénticos al oráculo offline; los 1007964 píxeles protegidos de las
variantes 2× quedan intactos. Los fixtures de presentación comprueban el período
del mapa, desplazamiento parcial, cambios CGRAM, brillo cero, blanking y
exclusiones. No alteran la lógica del juego. La prueba de Crateria también pasó
después de esta ampliación. Informes: `docs/qa/native_ceres_art_*` y
`native_art_verification.json`. Este resultado cubre ese fondo y esas salas;
el resto del redibujado y la campaña completa siguen pendientes.

La continuación hasta Brinstar verde añade siete grupos
`native_green_*_{original,enhanced,oracle}.png`: partida cargada, Parlor, pozo
de piratas, Lower Mushrooms, ascensor, llegada y control en Brinstar. Los
401408 píxeles originales coinciden con el oráculo offline en
`native_green_verification.json`. Las variantes 2× mantienen el filtro actual;
este recorrido no añade otros redibujados. El fondo nuevo de Ceres sigue
limitado a sus tres salas y el de Crateria a Landing Site.

## Tiles BG2 de Brinstar verde

`extract_green_bg2.py` decodifica 66 tiles 4bpp de la paleta 7 del pozo principal
(`9AD9`, estado `9AE6`), a partir de un paquete nativo de VRAM/CGRAM. La sala
original usa `LibBG_Brinstar_6_Vertical_GlowPatches` (`8F:BA37`). El atlas mantiene
16 columnas y las filas originales 14–21; los tiles no usados quedan negros.
ImageGen redibuja las formas azules de roca y raíces dentro de esa distribución.

El shader lee los IDs y giros de la tilemap BG2 que está en VRAM, usando su
scroll por línea. Muestrea cada pieza del atlas nuevo por separado y evita
filtrar fuera de sus límites. Mantiene las animaciones de CGRAM 113–127,
ventanas, color math, brillo y blanking. Conserva un 18% de la contribución
original y protege HUD, BG1, sprites y los píxeles Scale2x copiados de otra
celda. F1 devuelve el renderizado original del mismo estado nativo.

El cambio está limitado a esa sala/estado y a los 66 IDs extraídos; no añade
redibujados de personajes ni de las demás salas. El juego completo y el resto
del redibujado siguen pendientes.

`verify_green_art.py` pasó con 5316 ticks de continuación, nueve capturas
originales/restauradas (516096 píxeles RGB exactos) y 1830828 píxeles protegidos
sin cambios. Incluye tres alturas con el muro BG2 visible; un cálculo
independiente de 433838 muestras del atlas comprobó IDs, giros y CGRAM con
error máximo de un nivel RGB. Scroll, selección de sala/estado, fade y blanking
conservan la composición; los fixtures de prueba
modifican sólo copias del paquete de dibujo. Ceres y Crateria volvieron a pasar
sus regresiones. La ROM y SRAM fuente quedaron intactas. Informes y capturas:
`docs/qa/native_green_art_*`.

## Rocas de Parlor

El atlas `assets/remastered/parlor_bg2_tiles.png` se generó con la herramienta
integrada image_gen a partir de los 44 tiles originales. Su tamaño es
1448×1086, con celdas de 181×181 en una cuadrícula 8×6. La referencia extraída
mide 64×48; las cuatro celdas sin ID original no se muestrean en gameplay.
Se mantienen los grupos de roca oscura y su paleta de azul/verde, añadiendo
fracturas y relieve fino. El prompt exacto se guarda en
`assets/remastered/parlor_bg2_tiles.prompt.txt`; el JSON conserva hashes,
dimensiones y procedencia.

La integración utiliza los índices, giros y registros de scroll/CGRAM
originales de Parlor `92FD/9314` y `92FD/932E`. El atlas activo comparte un
sampler con Brinstar verde y Big Pink. F1 restaura el original. La prueba
`verify_parlor_art.py` usa dos recorridos de botones normales y un oráculo
PPU offline; sus capturas son del viewport propio de Godot. El estado del
escape final y las otras salas de esta biblioteca quedan pendientes.
