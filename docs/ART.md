# Arte y trazabilidad

Los gráficos originales se decodifican de la ROM local identificada en `assets/extracted/manifest.json`. Los assets mejorados no sobrescriben los originales.

- `assets/extracted/tilesets/*_original.png`: metatiles de 16×16, atlas de 32×32 celdas, tiles SNES 4bpp y paletas originales.
- `*_enhanced.png`: metatiles de 64×64, cada celda ampliada independientemente con Scale2x dos veces. Se conserva su índice.
- `assets/extracted/samus/`: 19 conjuntos de animación (nueve movimientos en ambos sentidos y pose frontal del ascensor). Cada frame original ocupa 64×64 y usa el centro [32,32] como anclaje OAM.
- `assets/extracted/objects/elevator_*.png`: los dos cuadros de $A3:962F/9645, con tiles comunes de $9A:D200 y paleta de sprites 5; versiones original y 4×. `elevator.json` conserva la trazabilidad de sus constantes.
- `assets/extracted/objects/`: atlas de tiles de 154 encabezados de enemigo, nave ensamblada con offsets de inicialización de la ROM y cinco conjuntos de animación. Los piratas grises de suelo/pared suman 55 frames de spritemaps compuestos con offsets e hitboxes originales; los 11 frames de láser usan los tiles comunes y la paleta de sprites 5. Todos tienen variantes 4×.
- `assets/extracted/items/`: gráficos de 17 mejoras dinámicas, decodificados desde el banco $89; dos frames y variantes con las paletas de los 29 tilesets. Los tanques usan los metatiles CRE $4A–$51.
- `assets/remastered/crateria_backdrop.png`: fondo nuevo, destinado al proyecto, creado con la herramienta integrada ImageGen usando `assets/extracted/references/crateria_reference.png` como referencia de colores y terreno. No altera colisiones.

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
No se generó otra imagen en esta integración: se reutiliza el fondo creado con
ImageGen y el prompt documentado arriba, basado en la referencia extraída.

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
