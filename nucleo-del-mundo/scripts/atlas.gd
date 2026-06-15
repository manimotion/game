# =============================================================
# atlas.gd — Autoload "Atlas" (Fase 5B: arte)
# Genera TODO el arte del juego por código al arrancar: texturas
# de tiles con variantes, césped de superficie, grietas, sprites
# del jugador (animados, con capas para las skins), slime y
# fondos (cielo, sol, nubes, colinas). Pixel art 16x16 dibujado
# a 32px (filtro NEAREST global en project.godot).
# La PALETA es una sola y armónica: cambiar un color aquí lo
# cambia en todo el juego. Para arte de artista real: reemplazar
# estas texturas por PNGs manteniendo la misma API pública.
# =============================================================
extends Node

const PX := 16                 # lado de la textura de un tile
const VARIANTS := 4            # variantes por tipo de tile (look natural)

# Tipos de tile — DEBEN coincidir con world.gd
const T_DIRT := 1
const T_STONE := 2
const T_ORE := 3
const T_BEDROCK := 4
const T_WOOD := 5
const T_LEAF := 6
const T_WALL := 7
const T_CAMPFIRE := 8
const T_SPIKES := 9
const T_TOWER := 10
const T_NEST := 11
const T_CRYSTAL := 12
const T_WATER := 13
const T_FEATHER := 14
const T_AETHER := 15
const T_DIAMOND := 16
const T_EMBER := 17
const T_TOWER_MEGA := 18
const T_RAIL := 19            # vía de tren abandonada (Bloque 3)
const T_CHEST := 20           # cofre de recursos (Bloque 3)
const T_SKULL := 21           # calavera estilo Halo (Bloque 3)

# ---- PALETA (tierras cálidas + verdes naturales, saturación contenida) ----
const P_DIRT := Color("9b6a42")
const P_DIRT_D := Color("6e4426")
const P_DIRT_L := Color("b07b4f")
const P_GRASS := Color("6abe30")
const P_GRASS_D := Color("4a8f22")
const P_GRASS_L := Color("8ad94a")
const P_STONE := Color("7e8490")
const P_STONE_D := Color("5a5f6b")
const P_STONE_L := Color("9aa1ad")
const P_GOLD := Color("f0c040")
const P_GOLD_L := Color("ffe890")
const P_GOLD_D := Color("a87820")
const P_BEDROCK := Color("23232c")
const P_BEDROCK_D := Color("16161d")
const P_WOOD := Color("7a4e2a")
const P_WOOD_D := Color("5e3a1e")
const P_WOOD_L := Color("8f5f36")
const P_LEAF := Color("4e9b3c")
const P_LEAF_D := Color("3e7e30")
const P_LEAF_L := Color("66b54e")
const P_WALL := Color("5a5a68")
const P_WALL_D := Color("3e3e4a")
const P_WALL_L := Color("7a7a8a")
const P_FIRE := Color("f0a030")
const P_FIRE_L := Color("f0d868")
const P_FIRE_D := Color("c04020")
const P_LOG := Color("5a3a1e")
const P_LOG_D := Color("3e2a14")
const P_SPIKE := Color("c4c8d4")
const P_SPIKE_D := Color("4a4a55")
const P_SPIKE_L := Color("eef0f6")
const P_NEST := Color("4a3a2e")
const P_NEST_D := Color("332720")
const P_NEST_L := Color("6b5240")
const P_NEST_GLOW := Color("ff6a3c")
const P_DRILL := Color("8a8f9b")
const P_DRILL_D := Color("5a5f6b")
const P_DRILL_BIT := Color("f0c040")
const P_MOLE := Color("6b4a3a")
const P_MOLE_D := Color("4a3226")
const P_MOLE_CLAW := Color("e8e0d0")
const P_RAM := Color("c46a3a")
const P_RAM_D := Color("8a4422")
const P_RAM_HORN := Color("e8e0d0")
const P_CRYSTAL := Color("5ad0e6")
const P_CRYSTAL_L := Color("d4faff")
const P_CRYSTAL_D := Color("2f8aa0")
const P_CRYSTAL_CORE := Color("b070ff")
# Bloque 1 "Mundo vivo": minerales de bioma aéreo (pluma/esencia) y
# profundo (diamante/ascua) + agua de los ríos del subsuelo.
const P_FEATHER_L := Color("fffaf0")
const P_FEATHER_PINK := Color("f4b8c8")
const P_FEATHER_BLUE := Color("b8d4f4")
const P_FEATHER_MINT := Color("b8f4d4")
const P_AETHER := Color("3ad8a8")
const P_AETHER_L := Color("c8fff0")
const P_AETHER_D := Color("1e8a6e")
const P_AETHER_CORE := Color("eafffa")
const P_DIAMOND := Color("bfe9ff")
const P_DIAMOND_L := Color("ffffff")
const P_DIAMOND_D := Color("7ec4e8")
const P_DIAMOND_CORE := Color("e8fbff")
const P_EMBER := Color("e8542a")
const P_EMBER_L := Color("ffd23c")
const P_EMBER_D := Color("7a1f12")
const P_EMBER_CORE := Color("fff2a0")
const P_WATER := Color(0.20, 0.45, 0.85, 0.55)
const P_WATER_L := Color(0.35, 0.65, 0.95, 0.65)
# Bloque 3 "Mundo vivo II": vía de tren (raíles + traviesas), cofre de
# madera con herrajes dorados y calavera (hueso pálido + cuencas oscuras).
const P_RAIL_METAL := Color("9aa1ad")
const P_RAIL_METAL_L := Color("cfd6e0")
const P_RAIL_TIE := Color("5e3a1e")
const P_CHEST := Color("8a5a2e")
const P_CHEST_D := Color("5e3a1c")
const P_CHEST_L := Color("a87a44")
const P_CHEST_IRON := Color("d8b24a")
const P_SKULL := Color("e8e4d4")
const P_SKULL_D := Color("a89c80")
const P_SKULL_SHADOW := Color("3a3024")

const C_SKY_TOP := Color("3e7fc9")
const C_SKY_BOT := Color("a8d8f0")
const C_UNDER_TOP := Color("1a1622")
const C_UNDER_BOT := Color("0b0a10")
const C_HILL_FAR := Color("7da884")
const C_HILL_NEAR := Color("567d5e")
const C_SUN := Color("fff4c0")
const C_CLOUD := Color(1.0, 1.0, 1.0, 0.85)

# ---- Sprite del jugador (12x22 px, dibujado a 24x44) ----
const C_SKIN := Color("f0c8a0")
const C_HAIR := Color("4a3220")
const C_EYE := Color("1c1c24")
const C_PANTS := Color("3a4a6b")
const C_PANTS_D := Color("2c3852")
const C_BOOT := Color("5a3a22")

# Letras: O=contorno(capa), S=piel, H=pelo, E=ojo, P/p=pantalón,
# F=bota, B/b=camisa(capa, se tiñe con el color de la skin)
const HEAD := [
	"...OOOOOO...",
	"..OHHHHHHO..",
	".OHHHHHHHHO.",
	".OHHSSSSHHO.",
	".OSSESSESSO.",
	".OSSSSSSSSO.",
	"..OSSSSSSO..",
	"..OOSSSSOO..",
]
const TORSO := [
	".OBBBBBBBBO.",
	"OBBbBBBBbBBO",
	"OBBbBBBBbBBO",
	"OBBbBBBBbBBO",
	"OSSbBBBBbSSO",
	".OBBBBBBBBO.",
	".OPPPPPPPPO.",
]
const LEGS_IDLE := [
	".OPPPPPPPPO.",
	"..OPP..PPO..",
	"..OPP..PPO..",
	"..OPP..PPO..",
	"..OPp..pPO..",
	"..OFF..FFO..",
	"..OOO..OOO..",
]
const LEGS_W1 := [
	".OPPPPPPPPO.",
	".OPPP..PPPO.",
	".OPP....PPO.",
	".OPp....pPO.",
	"..OP....PO..",
	".OFF....FFO.",
	".OOO....OOO.",
]
const LEGS_W2 := [
	".OPPPPPPPPO.",
	"..OPP..PPO..",
	"..OPP..PPO..",
	"..OPp..PPO..",
	"..OPP..pPO..",
	"..OFF..FFO..",
	"..OOO..OO...",
]
const LEGS_JUMP := [
	".OPPPPPPPPO.",
	".OPP....PPO.",
	"..OPp..pPO..",
	"..OFF..FFO..",
	"..OOO..OOO..",
	"............",
	"............",
]

# Accesorios de skin (rediseño): silueta de identidad sobre la cabeza.
# X = pixel del accesorio (se tiñe con el acento de la skin). 12 de ancho,
# las primeras filas se solapan con la cabeza del jugador (HEAD, filas 0-7).
const ACC_CORONA := [           # corona: royalty
	"..X..XX..X..",
	"..XXXXXXXX..",
]
const ACC_CUERNOS := [          # cuernos: demonio
	".X........X.",
	".X........X.",
	"..X......X..",
]
const ACC_CAPUCHA := [          # capucha: asesino/sombra (enmarca la cara)
	"...XXXXXX...",
	"..XXXXXXXX..",
	".XXXXXXXXXX.",
	".XX......XX.",
	".XX......XX.",
	"..X......X..",
]
const ACC_VISOR := [            # visor cyber: banda sobre los ojos
	"............",
	"............",
	"............",
	"............",
	".XXXXXXXXXX.",
]
const ACC_CASCO := [            # casco: caballero/minero
	"...XXXXXX...",
	"..XXXXXXXX..",
	".XXXXXXXXXX.",
	".X........X.",
]
const ACC_OREJAS := [           # orejas puntiagudas: nocturna/bestia
	".XX......XX.",
	".XX......XX.",
	"..X......X..",
]
const ACC_HALO := [             # halo flotante: divino
	"...XXXXXX...",
	"..X......X..",
]
const ACC_DIADEMA := [          # diadema con gema: skins de gema
	"............",
	"............",
	".XXXXXXXXXX.",
	".....XX.....",
]

# ---- API pública (llenada en _ready) ----
var tiles: Dictionary = {}     # tipo -> Array[ImageTexture] (variantes)
var grass: Array = []          # variantes de tierra con césped encima
var deco: Array = []           # decoración de superficie: hierba alta y flores
var cracks: Array = []         # 3 overlays de grietas (leve → grave)
var avg: Dictionary = {}       # tipo -> Color promedio (para partículas)
var player_frames: Dictionary = {}  # "idle"/"walk"/"jump" -> Array[{outline,skin,hair,shirt,pants,boot}]
var player_acc: Dictionary = {}     # accesorio de skin -> ImageTexture (rediseño)
var slimes: Dictionary = {}    # variante ("normal"/"grande"/"dorado") -> ImageTexture
var sky_tex: GradientTexture2D
var under_tex: GradientTexture2D
var cloud_tex: ImageTexture
var hill_far_tex: ImageTexture
var hill_near_tex: ImageTexture
var arrow_tex: ImageTexture    # proyectil de la torre de flechas (Fase 8)


func _ready() -> void:
	for t in [T_DIRT, T_STONE, T_ORE, T_BEDROCK, T_WOOD, T_LEAF, T_WALL, T_CAMPFIRE, T_SPIKES, T_TOWER, T_NEST, T_CRYSTAL,
			T_WATER, T_FEATHER, T_AETHER, T_DIAMOND, T_EMBER, T_TOWER_MEGA, T_RAIL, T_CHEST, T_SKULL]:
		tiles[t] = []
		for v in VARIANTS:
			tiles[t].append(_make_tile(t, v))
	for v in VARIANTS:
		grass.append(_make_grass(v))
	for v in 4:
		deco.append(_make_deco(v))
	for lvl in 3:
		cracks.append(_make_crack(lvl))
	player_frames = {
		"idle": [_build_frame(HEAD + TORSO + LEGS_IDLE)],
		"walk": [
			_build_frame(HEAD + TORSO + LEGS_W1),
			_build_frame(HEAD + TORSO + LEGS_W2),
			_build_frame(HEAD + TORSO + _mirror(LEGS_W1)),
			_build_frame(HEAD + TORSO + _mirror(LEGS_W2)),
		],
		"jump": [_build_frame(HEAD + TORSO + LEGS_JUMP)],
	}
	player_acc = {
		"corona": _make_acc(ACC_CORONA),
		"cuernos": _make_acc(ACC_CUERNOS),
		"capucha": _make_acc(ACC_CAPUCHA),
		"visor": _make_acc(ACC_VISOR),
		"casco": _make_acc(ACC_CASCO),
		"orejas": _make_acc(ACC_OREJAS),
		"halo": _make_acc(ACC_HALO),
		"diadema": _make_acc(ACC_DIADEMA),
	}
	# Variantes de NPC (npc_manager.KINDS): slimes con otra paleta
	# + el murciélago nocturno (Fase 6)
	slimes["normal"] = _make_slime(Color("3fae4a"), Color("2c8338"), Color("8fe093"))
	slimes["grande"] = _make_slime(Color("8a4ad0"), Color("5c2f96"), Color("c9a0f0"), "grande")
	slimes["slime_mega"] = _make_slime(Color("4a2a70"), Color("301a4a"), Color("9a6ad0"), "mega")
	slimes["dorado"] = _make_slime(P_GOLD, P_GOLD_D, P_GOLD_L, "dorado")
	slimes["murcielago"] = _make_bat()
	slimes["jefe"] = _make_boss()
	# Fase 10: nuevos enemigos (taladro, topo, embistedor) y jefes alternativos
	slimes["taladro"] = _make_drill(P_DRILL, P_DRILL_D, P_DRILL_BIT)
	slimes["topo"] = _make_mole(P_MOLE, P_MOLE_D, P_MOLE_CLAW)
	slimes["embistedor"] = _make_charger(P_RAM, P_RAM_D, P_RAM_HORN)
	# Rediseño 2026-06-13: cada jefe con su SILUETA, no el demonio recoloreado
	slimes["jefe_murcielago"] = _make_boss_bat()
	slimes["jefe_topo"] = _make_boss_mole()
	slimes["jefe_corredor"] = _make_boss_runner()
	# Bloque 4 "Bestiario vivo" (rediseño: silueta propia, no slime recoloreado):
	# espectro flotante, coracero blindado y sanador con cruz curativa. El
	# espectro se dibuja translúcido en npc_manager._draw (flag "ghost").
	slimes["espectro"] = _make_ghost()
	slimes["coracero"] = _make_armor()
	slimes["sanador"] = _make_healer()
	sky_tex = _make_gradient(C_SKY_TOP, C_SKY_BOT)
	under_tex = _make_gradient(C_UNDER_TOP, C_UNDER_BOT)
	cloud_tex = _make_cloud()
	hill_far_tex = _make_hills(C_HILL_FAR, 11)
	hill_near_tex = _make_hills(C_HILL_NEAR, 23)
	arrow_tex = _make_arrow()


## Textura del tile en coord: variante estable por posición (look natural).
## Tierra con aire encima = césped.
func tile_tex(t: int, coord: Vector2i, air_above: bool) -> Texture2D:
	var v := int(_h(coord.x, coord.y, 7) * VARIANTS) % VARIANTS
	if t == T_DIRT and air_above:
		return grass[v]
	return tiles.get(t, tiles[T_DIRT])[v]


func avg_color(t: int) -> Color:
	return avg.get(t, P_DIRT)


# -------------------------------------------------------------
# GENERACIÓN DE TILES
# -------------------------------------------------------------
## Hash determinista 0..1 (mismo resultado en todos los peers).
func _h(x: int, y: int, s: int) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 982451653) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


## Bisel suave: ilumina arriba/izquierda, oscurece abajo/derecha.
func _bevel(img: Image) -> void:
	for x in PX:
		img.set_pixel(x, 0, img.get_pixel(x, 0).lightened(0.10))
		img.set_pixel(x, PX - 1, img.get_pixel(x, PX - 1).darkened(0.14))
	for y in PX:
		img.set_pixel(0, y, img.get_pixel(0, y).lightened(0.05))
		img.set_pixel(PX - 1, y, img.get_pixel(PX - 1, y).darkened(0.08))


func _make_tile(t: int, v: int) -> ImageTexture:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	var sum := Color(0, 0, 0)
	for y in PX:
		for x in PX:
			img.set_pixel(x, y, _tile_pixel(t, v, x, y))
	match t:
		T_DIRT, T_STONE, T_ORE, T_LEAF, T_WALL, T_TOWER, T_NEST, T_CRYSTAL, T_FEATHER, T_AETHER, T_DIAMOND, T_EMBER, T_TOWER_MEGA, T_CHEST, T_SKULL:
			_bevel(img)
	# color promedio (para las partículas de minado)
	for y in PX:
		for x in PX:
			sum += img.get_pixel(x, y)
	avg[t] = Color(sum.r / (PX * PX), sum.g / (PX * PX), sum.b / (PX * PX))
	return ImageTexture.create_from_image(img)


func _tile_pixel(t: int, v: int, x: int, y: int) -> Color:
	var n := _h(x + v * 31, y + v * 17, t)        # grano por pixel
	match t:
		T_DIRT:
			var c := P_DIRT.lerp(P_DIRT_L, n * 0.45)
			if _h(x, y, v + 40) < 0.08:           # piedritas oscuras
				c = P_DIRT_D
			return c
		T_STONE:
			var c := P_STONE.lerp(P_STONE_L, n * 0.35)
			# vetas horizontales quebradas (look de roca sedimentada)
			var vein := (y + int(_h(x / 4, v, 3) * 3.0)) % 6
			if vein == 0 and _h(x, y, v + 9) < 0.75:
				c = P_STONE_D
			return c
		T_ORE:
			var c := P_STONE.lerp(P_STONE_L, n * 0.3)
			# pepitas doradas en racimos
			var cx := int(_h(v, 1, 21) * 10.0) + 3
			var cy := int(_h(v, 2, 22) * 10.0) + 3
			for k in 3:
				var nx := cx + int(_h(v, k, 33) * 8.0) - 4
				var ny := cy + int(_h(v, k, 44) * 8.0) - 4
				var d := absi(x - nx) + absi(y - ny)
				if d <= 1:
					c = P_GOLD if d == 1 else P_GOLD_L
				elif d == 2 and c != P_GOLD and c != P_GOLD_L:
					if _h(x, y, k) < 0.5:
						c = P_GOLD_D
			return c
		T_BEDROCK:
			var c := P_BEDROCK
			if _h(x / 3, y / 3, v) < 0.4:
				c = P_BEDROCK_D
			return c
		T_WOOD:
			# tronco: franjas verticales + corteza oscura en los bordes
			var c := P_WOOD if (x / 3) % 2 == 0 else P_WOOD_L
			if x <= 1 or x >= PX - 2:
				c = P_WOOD_D
			if _h(x, y, v + 5) < 0.06:
				c = P_WOOD_D
			return c
		T_LEAF:
			var c := P_LEAF.lerp(P_LEAF_L, n * 0.5)
			if _h(x, y, v + 8) < 0.10:
				c = P_LEAF_D
			return c
		T_WALL:
			# Muralla: ladrillos de piedra tallada con mortero (Fase 7)
			var row := y / 4
			var off := 4 if row % 2 != 0 else 0
			var bx := (x + off) % 8
			if y % 4 == 0 or bx == 0:
				return P_WALL_D
			var c := P_WALL.lerp(P_WALL_L, n * 0.3)
			if _h(x, y, v + 15) < 0.1:
				c = P_WALL_D.lerp(P_WALL, 0.5)
			return c
		T_CAMPFIRE:
			# Fogata: leños abajo, llama arriba (Fase 7)
			if y >= 12:
				if (y == 12 or y == 13) and x >= 3 and x <= 12:
					return P_LOG if _h(x, y, v + 20) > 0.3 else P_LOG_D
				return Color.TRANSPARENT
			var fx := absf(float(x) - 7.5)
			var fy := float(12 - y)
			var fw := 5.0 * (1.0 - fy / 14.0)
			if fx < fw and fy > 0:
				var heat := (1.0 - fx / fw) * (1.0 - fy / 14.0)
				if heat > 0.55:
					return P_FIRE_L
				elif heat > 0.25:
					return P_FIRE
				return P_FIRE_D
			return Color.TRANSPARENT
		T_SPIKES:
			# Trampa de pinchos: picos de metal sobre base oscura (Fase 8)
			if y >= 13:
				return P_SPIKE_D
			var heights := [3, 9, 13, 9, 3]
			var height: int = heights[x % 5]
			if y >= 13 - height:
				return P_SPIKE_L if x % 5 == 2 else P_SPIKE
			return Color.TRANSPARENT
		T_TOWER:
			# Torre de flechas: puesto de vigía de madera + tronera sobre base de piedra (Fase 8)
			if y < 5:
				if x >= 6 and x <= 9 and y >= 2:
					return C_UNDER_TOP
				return P_LOG if (x + y) % 3 != 0 else P_LOG_D
			var row := (y - 5) / 4
			var off := 4 if row % 2 != 0 else 0
			var bx := (x + off) % 8
			if (y - 5) % 4 == 0 or bx == 0:
				return P_WALL_D
			return P_WALL.lerp(P_WALL_L, n * 0.3)
		T_NEST:
			# Nido (Fase 10): masa orgánica tejida con núcleo brillante
			var c := P_NEST.lerp(P_NEST_L, n * 0.3)
			var ddx := float(x) - 7.5
			var ddy := float(y) - 7.5
			var dd := ddx * ddx + ddy * ddy
			if dd < 5.0:
				return P_NEST_GLOW
			elif dd < 11.0:
				return P_NEST_GLOW.darkened(0.35)
			if _h(x, y, v + 25) < 0.12:
				c = P_NEST_D
			return c
		T_CRYSTAL:
			# Cristal: matriz de piedra oscura con un racimo de cristales cian/violeta
			# (bioma aéreo y subterráneo profundo — recurso para el pico de cristal)
			var c := P_STONE_D.lerp(P_STONE, n * 0.3)
			var cx := int(_h(v, 1, 51) * 10.0) + 3
			var cy := int(_h(v, 2, 52) * 10.0) + 3
			for k in 3:
				var nx := cx + int(_h(v, k, 63) * 8.0) - 4
				var ny := cy + int(_h(v, k, 74) * 8.0) - 4
				var d := absi(x - nx) + absi(y - ny)
				if d <= 1:
					c = P_CRYSTAL_CORE if d == 0 else P_CRYSTAL_L
				elif d == 2 and c != P_CRYSTAL_CORE and c != P_CRYSTAL_L:
					c = P_CRYSTAL if _h(x, y, k + 80) < 0.5 else P_CRYSTAL_D
			return c
		T_FEATHER:
			# Pluma: matriz de piedra clara con un racimo de plumón en tonos
			# pastel (arcoíris tenue) — bioma aéreo (Bloque 1 "Mundo vivo")
			var c := P_STONE_D.lerp(P_STONE, n * 0.3)
			var cx := int(_h(v, 1, 91) * 10.0) + 3
			var cy := int(_h(v, 2, 92) * 10.0) + 3
			var pastels := [P_FEATHER_PINK, P_FEATHER_BLUE, P_FEATHER_MINT]
			for k in 3:
				var nx := cx + int(_h(v, k, 93) * 8.0) - 4
				var ny := cy + int(_h(v, k, 94) * 8.0) - 4
				var d := absi(x - nx) + absi(y - ny)
				if d <= 1:
					c = P_FEATHER_L if d == 0 else pastels[k]
				elif d == 2 and c != P_FEATHER_L and not pastels.has(c):
					c = P_FEATHER_L if _h(x, y, k + 95) < 0.5 else c
			return c
		T_AETHER:
			# Esencia: matriz de piedra oscura con un racimo de energía
			# cian/verde brillante (transmite curación) — núcleo raro del
			# bioma aéreo (Bloque 1 "Mundo vivo")
			var c := P_STONE_D.lerp(P_STONE, n * 0.3)
			var cx := int(_h(v, 1, 101) * 10.0) + 3
			var cy := int(_h(v, 2, 102) * 10.0) + 3
			for k in 3:
				var nx := cx + int(_h(v, k, 103) * 8.0) - 4
				var ny := cy + int(_h(v, k, 104) * 8.0) - 4
				var d := absi(x - nx) + absi(y - ny)
				if d <= 1:
					c = P_AETHER_CORE if d == 0 else P_AETHER_L
				elif d == 2 and c != P_AETHER_CORE and c != P_AETHER_L:
					c = P_AETHER if _h(x, y, k + 105) < 0.5 else P_AETHER_D
			return c
		T_DIAMOND:
			# Diamante: matriz de piedra clara con un racimo blanco/celeste muy
			# brillante, más "limpio" que el cristal — núcleo más raro del
			# bioma profundo (Bloque 1 "Mundo vivo")
			var c := P_STONE_L.lerp(P_DIAMOND, n * 0.4)
			var cx := int(_h(v, 1, 111) * 10.0) + 3
			var cy := int(_h(v, 2, 112) * 10.0) + 3
			for k in 3:
				var nx := cx + int(_h(v, k, 113) * 8.0) - 4
				var ny := cy + int(_h(v, k, 114) * 8.0) - 4
				var d := absi(x - nx) + absi(y - ny)
				if d <= 1:
					c = P_DIAMOND_CORE if d == 0 else P_DIAMOND_L
				elif d == 2 and c != P_DIAMOND_CORE and c != P_DIAMOND_L:
					c = P_DIAMOND if _h(x, y, k + 115) < 0.5 else P_DIAMOND_D
			return c
		T_EMBER:
			# Ascua: matriz de piedra oscurecida por el calor con un racimo de
			# brasas incandescentes — bioma profundo, junto a los ríos de agua
			# (Bloque 1 "Mundo vivo")
			var c := P_STONE_D.lerp(P_EMBER_D, n * 0.5)
			var cx := int(_h(v, 1, 121) * 10.0) + 3
			var cy := int(_h(v, 2, 122) * 10.0) + 3
			for k in 3:
				var nx := cx + int(_h(v, k, 123) * 8.0) - 4
				var ny := cy + int(_h(v, k, 124) * 8.0) - 4
				var d := absi(x - nx) + absi(y - ny)
				if d <= 1:
					c = P_EMBER_CORE if d == 0 else P_EMBER_L
				elif d == 2 and c != P_EMBER_CORE and c != P_EMBER_L:
					c = P_EMBER if _h(x, y, k + 125) < 0.5 else P_EMBER_D
			return c
		T_WATER:
			# Agua: textura traslúcida azul con líneas de onda — no es un
			# mineral, no lleva matriz de piedra (Bloque 1 "Mundo vivo")
			var c := P_WATER
			if (y + int(_h(x, v, 130) * 3.0)) % 6 < 1:
				c = P_WATER_L
			return c
		T_TOWER_MEGA:
			# Torre mega (Bloque 2): mismo puesto de vigía de T_TOWER, pero con
			# la tronera y los engastes de la base en diamante/cristal —
			# torre mejorada con minerales del subsuelo profundo
			if y < 5:
				if x >= 6 and x <= 9 and y >= 2:
					return P_DIAMOND_CORE if (x + y) % 2 == 0 else C_UNDER_TOP
				return P_LOG if (x + y) % 3 != 0 else P_LOG_D
			var row := (y - 5) / 4
			var off := 4 if row % 2 != 0 else 0
			var bx := (x + off) % 8
			if (y - 5) % 4 == 0 or bx == 0:
				return P_DIAMOND_D if (x + y) % 5 == 0 else P_WALL_D
			if bx == 4:
				return P_DIAMOND.lerp(P_DIAMOND_L, n * 0.3)
			return P_WALL.lerp(P_WALL_L, n * 0.3)
		T_RAIL:
			# Vía de tren (Bloque 3): dos raíles metálicos horizontales sobre
			# traviesas de madera; el resto transparente (se ve la cueva).
			if y == 5 or y == 10:
				return P_RAIL_METAL_L if _h(x, y, v + 70) < 0.4 else P_RAIL_METAL
			if y >= 6 and y <= 9 and x % 4 == 1:
				return P_RAIL_TIE   # traviesas verticales bajo los raíles
			return Color.TRANSPARENT
		T_CHEST:
			# Cofre (Bloque 3): caja de madera con tapa, herrajes y cerradura
			# dorada. Margen exterior transparente para que "flote" sobre el suelo.
			if x < 2 or x > 13 or y < 3 or y > 14:
				return Color.TRANSPARENT
			if x == 2 or x == 13 or y == 3 or y == 14:
				return P_CHEST_D   # contorno/herraje oscuro
			if y == 7 or y == 8:
				return P_CHEST_IRON   # banda metálica de la tapa
			if x >= 7 and x <= 8 and y >= 7 and y <= 10:
				return P_CHEST_IRON   # cerradura central
			var cc := P_CHEST.lerp(P_CHEST_L, n * 0.4)
			if _h(x, y, v + 80) < 0.12:
				cc = P_CHEST_D.lerp(P_CHEST, 0.5)   # vetas de la madera
			return cc
		T_SKULL:
			# Calavera (Bloque 3, estilo Halo): cráneo pálido con cuencas y
			# nariz oscuras + fila de dientes. Enterrada en roca; todas iguales
			# (el jugador no sabe si es buena o mala hasta excavarla).
			if x < 3 or x > 12 or y < 2 or y > 13:
				return Color.TRANSPARENT
			if y >= 5 and y <= 7 and ((x >= 4 and x <= 6) or (x >= 9 and x <= 11)):
				return P_SKULL_SHADOW   # cuencas de los ojos
			if y >= 8 and y <= 9 and x >= 7 and x <= 8:
				return P_SKULL_SHADOW   # nariz
			if y >= 11 and x % 2 == 0:
				return P_SKULL_SHADOW   # dientes
			return P_SKULL if _h(x, y, v + 90) > 0.2 else P_SKULL_D
	return P_DIRT


## Tierra con manto de césped (borde irregular + briznas).
func _make_grass(v: int) -> ImageTexture:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	for y in PX:
		for x in PX:
			img.set_pixel(x, y, _tile_pixel(T_DIRT, v, x, y))
	for x in PX:
		var depth := 3 + int(_h(x, v, 12) * 3.0)   # borde irregular 3..5 px
		for y in depth:
			var g := P_GRASS
			if y == 0:
				g = P_GRASS_L
			elif y == depth - 1:
				g = P_GRASS_D
			elif _h(x, y, v + 60) < 0.25:
				g = P_GRASS_D.lerp(P_GRASS, 0.5)
			img.set_pixel(x, y, g)
	_bevel(img)
	return ImageTexture.create_from_image(img)


## Decoración de superficie sobre el césped: matas de hierba alta
## (v 0-1) y flores rojas/amarillas (v 2-3). Se dibujan en el tile
## de AIRE encima del césped (chunk_renderer) — puro adorno.
func _make_deco(v: int) -> ImageTexture:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	if v < 2:
		for b in 5:
			var x := 2 + int(_h(b, v, 121) * 12.0)
			var hgt := 3 + int(_h(b, v, 122) * 4.0)
			var col := P_GRASS_L if _h(b, v, 123) < 0.5 else P_GRASS
			for k in hgt:
				img.set_pixel(x, PX - 1 - k, col)
	else:
		var px := 7
		for k in 6:
			img.set_pixel(px, PX - 1 - k, P_GRASS_D)
		img.set_pixel(px - 1, PX - 3, P_GRASS)
		img.set_pixel(px + 1, PX - 4, P_GRASS)
		var petal := Color("e04848") if v == 2 else Color("f0c040")
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			img.set_pixel(px + off.x, PX - 7 + off.y, petal)
		img.set_pixel(px, PX - 7, Color("fff0c0"))
	return ImageTexture.create_from_image(img)


## Overlay de grietas (paseo aleatorio desde el centro).
func _make_crack(lvl: int) -> ImageTexture:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	var col := Color(0, 0, 0, 0.45 + lvl * 0.12)
	for w in (2 + lvl * 2):
		var x := PX / 2
		var y := PX / 2
		for step in (4 + lvl * 3):
			if x >= 0 and x < PX and y >= 0 and y < PX:
				img.set_pixel(x, y, col)
			var d := _h(w, step, lvl + 70)
			if d < 0.25:
				x += 1
			elif d < 0.5:
				x -= 1
			elif d < 0.75:
				y += 1
			else:
				y -= 1
	return ImageTexture.create_from_image(img)


# -------------------------------------------------------------
# SPRITE DEL JUGADOR (3 capas: contorno y camisa se tiñen por skin)
# -------------------------------------------------------------
## Rediseño 2026-06-13: el jugador se separa en MÁS capas tintables para que
## las skins sean un atuendo completo (camisa + pantalón + pelo + borde), no
## solo un color de camisa. `skin` (cara/ojos) y `boot` quedan fijas. Las
## capas tintables se generan en BLANCO y player.gd las tiñe por skin.
func _build_frame(rows: Array) -> Dictionary:
	var skin := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	var hair := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	var shirt := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	var pants := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	var boot := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	var outline := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in 12:
			match row[x]:
				"O": outline.set_pixel(x, y, Color.WHITE)
				"S": skin.set_pixel(x, y, C_SKIN)
				"E": skin.set_pixel(x, y, C_EYE)
				"H": hair.set_pixel(x, y, Color.WHITE)
				"P": pants.set_pixel(x, y, Color.WHITE)
				"p": pants.set_pixel(x, y, Color(0.74, 0.74, 0.74))
				"F": boot.set_pixel(x, y, C_BOOT)
				"B": shirt.set_pixel(x, y, Color.WHITE)
				"b": shirt.set_pixel(x, y, Color(0.78, 0.78, 0.78))
	return {"outline": ImageTexture.create_from_image(outline),
		"skin": ImageTexture.create_from_image(skin),
		"hair": ImageTexture.create_from_image(hair),
		"shirt": ImageTexture.create_from_image(shirt),
		"pants": ImageTexture.create_from_image(pants),
		"boot": ImageTexture.create_from_image(boot)}


## Accesorio de skin (rediseño): silueta distintiva sobre la cabeza/hombros
## (corona, cuernos, capucha, visor, casco, orejas, halo, diadema). Blanco;
## player.gd lo tiñe con el color de acento de la skin equipada.
func _make_acc(acc_rows: Array) -> ImageTexture:
	var img := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	for y in acc_rows.size():
		var row: String = acc_rows[y]
		for x in mini(row.length(), 12):
			if row[x] == "X":
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _mirror(rows: Array) -> Array:
	var out := []
	for r: String in rows:
		out.append(r.reverse())
	return out


# -------------------------------------------------------------
# SLIME, CIELO, NUBES Y COLINAS
# -------------------------------------------------------------
## Slime con CARÁCTER (rediseño 2026-06-13): cara expresiva (ojos grandes +
## boca) y un `style` por variante — "" amistoso, "grande" furioso, "mega"
## agrietado/feroz, "dorado" con corona y destello. Nada de bola plana.
func _make_slime(body: Color, body_d: Color, shine: Color, style := "") -> ImageTexture:
	var img := Image.create(16, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 16:
			# elipse (cuerpo gelatinoso)
			var dx := (x - 7.5) / 7.5
			var dy := (y - 6.5) / 5.5
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var c := body.lerp(body_d, clampf((dx + dy + 1.2) * 0.4, 0.0, 1.0))
			if d > 0.82:
				c = body_d
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.92))
	# brillo gelatinoso arriba-izquierda
	for p in [[4, 2], [5, 2], [4, 3]]:
		img.set_pixel(p[0], p[1], shine)
	# OJOS grandes (2x2 blanco + pupila) — dan personalidad
	for ex in [5, 9]:
		img.set_pixel(ex, 5, Color.WHITE)
		img.set_pixel(ex + 1, 5, Color.WHITE)
		img.set_pixel(ex, 6, Color.WHITE)
		img.set_pixel(ex + 1, 6, Color.WHITE)
		img.set_pixel(ex + 1, 6, Color("1c1c24"))   # pupila
	# Detalles por variante
	match style:
		"grande":   # cejas furiosas + boca recta
			for bx in [4, 5]:
				img.set_pixel(bx, 4, body_d)
			for bx in [10, 11]:
				img.set_pixel(bx, 4, body_d)
			for mx in range(6, 10):
				img.set_pixel(mx, 9, Color("2a1430"))
		"mega":     # cejas + núcleo agrietado brillante + colmillos
			for bx in [4, 5]:
				img.set_pixel(bx, 4, body_d)
			for bx in [10, 11]:
				img.set_pixel(bx, 4, body_d)
			for cr in [[7, 3], [8, 4], [6, 8], [9, 9]]:
				img.set_pixel(cr[0], cr[1], shine)   # grietas/núcleo
			for mx in range(6, 10):
				img.set_pixel(mx, 9, Color("160820"))
			img.set_pixel(6, 10, Color.WHITE)        # colmillos
			img.set_pixel(9, 10, Color.WHITE)
		"dorado":   # sonrisa + corona + destello (botín brillante)
			for mx in range(6, 10):
				img.set_pixel(mx, 9, Color("5a3a10"))
			for cx in [5, 7, 9]:                      # corona de 3 puntas
				img.set_pixel(cx, 0, Color("fff0a0"))
				img.set_pixel(cx, 1, Color("ffd23c"))
			img.set_pixel(12, 3, Color.WHITE)         # destello
		_:          # normal: sonrisa amistosa
			img.set_pixel(6, 8, Color("2a1c12"))
			img.set_pixel(7, 9, Color("2a1c12"))
			img.set_pixel(8, 9, Color("2a1c12"))
			img.set_pixel(9, 8, Color("2a1c12"))
	return ImageTexture.create_from_image(img)


# -------------------------------------------------------------
# BESTIARIO CON IDENTIDAD (rediseño 2026-06-13): espectro/coracero/sanador
# dejan de ser slimes recoloreados y tienen su propia silueta. (El espectro
# se dibuja translúcido por el tinte "ghost" de npc_manager._draw; aquí va
# OPACO para que ese tinte module la transparencia.)
# -------------------------------------------------------------
## Espectro: espíritu flotante con cúpula redonda, faldón ondulado (3 lóbulos),
## cuencas huecas y boca tenue. Nada de slime.
func _make_ghost() -> ImageTexture:
	var w := 16
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var body := Color("cdd6f2")
	var body_d := Color("9aa6cc")
	for x in w:
		var dx := (float(x) - 7.5) / 7.0
		if absf(dx) > 1.0:
			continue
		# borde inferior ondulado: lóbulos colgantes (3) con muescas entre ellos
		var lobe: int = 14 if (x % 5) >= 1 and (x % 5) <= 3 else 11
		for y in range(0, lobe + 1):
			var dy := (float(y) - 7.0) / 7.0
			# cúpula superior: recorta las esquinas de arriba en redondo
			if y <= 8 and dx * dx + dy * dy > 1.0:
				continue
			var edge := absf(dx) > 0.72 or y >= lobe - 1
			img.set_pixel(x, y, body_d if edge else body)
	for ex in [5, 10]:                          # cuencas huecas
		img.set_pixel(ex, 6, Color("242038"))
		img.set_pixel(ex, 7, Color("242038"))
	img.set_pixel(7, 9, Color("3a3450"))        # boca tenue
	img.set_pixel(8, 9, Color("3a3450"))
	return ImageTexture.create_from_image(img)


## Coracero: blindado pesado — cuerpo de acero con placas, remaches y una
## ranura de visor con brillo rojo dentro.
func _make_armor() -> ImageTexture:
	var w := 18
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var metal := Color("8a909c")
	var metal_d := Color("5a606c")
	var metal_l := Color("c0c6d2")
	for y in h:
		for x in w:
			var dx := (float(x) - 9.0) / 8.5
			var dy := (float(y) - 8.0) / 7.5
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var c := metal_d if d > 0.72 else metal
			if y == 5 or y == 11:               # líneas de placa
				c = metal_d
			if y <= 3 and d < 0.6:              # brillo del yelmo
				c = metal_l
			img.set_pixel(x, y, c)
	for p in [[4, 8], [13, 8], [5, 13], [12, 13]]:   # remaches
		img.set_pixel(p[0], p[1], metal_l)
	for ex in range(6, 12):                     # ranura del visor
		img.set_pixel(ex, 8, Color("2a1010"))
	for ex in [7, 10]:                          # ojos rojos dentro
		img.set_pixel(ex, 8, Color("ff3030"))
	return ImageTexture.create_from_image(img)


## Sanador: cuerpo de menta con una CRUZ de curación brillante en el pecho
## y ojos suaves — lee como "apoyo/médico", no como slime.
func _make_healer() -> ImageTexture:
	var w := 16
	var h := 14
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var body := Color("46c98e")
	var body_d := Color("2e8a64")
	var glow := Color("e0fff0")
	for y in h:
		for x in w:
			var dx := (float(x) - 7.5) / 7.0
			var dy := (float(y) - 7.0) / 6.0
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			img.set_pixel(x, y, body_d if d > 0.72 else body)
	for y in range(4, 11):                       # barra vertical de la cruz
		img.set_pixel(7, y, glow)
		img.set_pixel(8, y, glow)
	for x in range(5, 11):                        # barra horizontal de la cruz
		img.set_pixel(x, 6, glow)
		img.set_pixel(x, 7, glow)
	for ex in [4, 11]:                            # ojos suaves
		img.set_pixel(ex, 5, Color("1c3a2a"))
	return ImageTexture.create_from_image(img)


# Murciélago (Fase 6): W = ala membranosa, B = cuerpo, E = ojo rojo
const BAT := [
	".W..........W.",
	"WWW........WWW",
	"WWWWBBBBBBWWWW",
	".WWWBEBBEBWWW.",
	"..WWBBBBBBWW..",
	"....BBBBBB....",
	".....B..B.....",
]


func _make_bat() -> ImageTexture:
	var img := Image.create(14, 7, false, Image.FORMAT_RGBA8)
	for y in BAT.size():
		var row: String = BAT[y]
		for x in row.length():
			match row[x]:
				"W": img.set_pixel(x, y, Color("4a3d66"))
				"B": img.set_pixel(x, y, Color("6b5b8e"))
				"E": img.set_pixel(x, y, Color("ff4040"))
	return ImageTexture.create_from_image(img)


# Jefe (Fase 9, pulido): demonio con cuernos, corona, cejas furiosas
# y colmillos. C=cuerno K=corona B=cuerpo D=sombra L=brillo
# W=blanco (ojos/dientes) R=pupila roja M=fauces
const BOSS := [
	"...CC.....KKKK.....CC...",
	"..CCC....KKKKKK....CCC..",
	"..CCC..BBBBBBBBBB..CCC..",
	"...CBBBBBBBBBBBBBBBBC...",
	"..BBBBBBBBBBBBBBBBBBBB..",
	".BBBLLBBBBBBBBBBBBBBBB..",
	".BBLLBBDDBBBBBBDDBBBBBB.",
	"BBBBBWWRBBBBBBBBRWWBBBBB",
	"BBBBBWWRBBBBBBBBRWWBBBBB",
	"BBBBBBBBBBBBBBBBBBBBBBBB",
	"BBBBBBBBBBBBBBBBBBBBBBBB",
	"BBBBMMMMMMMMMMMMMMMMBBBB",
	"BBBBMWWMMWWMMWWMMWWMBBBB",
	"BBBBMMMMMMMMMMMMMMMMBBBB",
	".BBBBBBBBBBBBBBBBBBBBBB.",
	".DBBBBBBBBBBBBBBBBBBBBD.",
	"..DDBBBBBBBBBBBBBBBBDD..",
	"....DDDDDDDDDDDDDDDD....",
]


# Paletas alternativas para BOSS (Fase 10): mismo molde de "demonio",
# recoloreado por tipo de jefe — mismo truco que los slimes (un molde,
# varias paletas). Cada letra de BOSS -> color.
const BOSS_PALETTE_DEMON := {
	"C": "3a3a45", "K": "f0c040", "B": "d6453f", "D": "7a1f1c",
	"L": "ffd9a0", "W": "ffffff", "R": "ff2020", "M": "4a0f0c",
}
const BOSS_PALETTE_BAT := {   # jefe_murcielago: morado nocturno
	"C": "2a2233", "K": "9a7ad0", "B": "4a3d66", "D": "2c2440",
	"L": "c9b8ff", "W": "ffffff", "R": "ff2020", "M": "1a1426",
}
const BOSS_PALETTE_MOLE := {  # jefe_topo: tierra y excavación
	"C": "3a2a1e", "K": "e8a040", "B": "8a5a3a", "D": "4a3226",
	"L": "f0c898", "W": "e8e0d0", "R": "ff2020", "M": "2a1c14",
}
const BOSS_PALETTE_RUNNER := {  # jefe_corredor: naranja veloz
	"C": "4a2a1a", "K": "ffe890", "B": "e07a30", "D": "a8501c",
	"L": "ffd9a0", "W": "ffffff", "R": "ff2020", "M": "4a1f0c",
}


func _make_boss(pal: Dictionary = BOSS_PALETTE_DEMON) -> ImageTexture:
	var img := Image.create(24, 18, false, Image.FORMAT_RGBA8)
	for y in BOSS.size():
		var row: String = BOSS[y]
		for x in row.length():
			var ch := row[x]
			if pal.has(ch):
				img.set_pixel(x, y, Color(String(pal[ch])))
	return ImageTexture.create_from_image(img)


# -------------------------------------------------------------
# JEFES CON IDENTIDAD PROPIA (rediseño 2026-06-13): cada jefe tiene su
# SILUETA, no el molde "demonio" recoloreado. Son versiones colosales y
# amenazantes de su criatura temática, dibujadas a procedimiento.
# -------------------------------------------------------------
## Murciélago Gigante: alas membranosas de borde dentado, orejas
## puntiagudas, ojos incandescentes y colmillos.
func _make_boss_bat() -> ImageTexture:
	var w := 30
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var body := Color("4a3d66")
	var body_d := Color("2c2440")
	var wing := Color("6b5b8e")
	var wing_d := Color("3a3050")
	for x in w:
		var off := absi(x - 15)
		if off >= 5 and off <= 14:
			var top := 5 - (off - 5) / 3       # la punta del ala sube
			var bot := 14 - (off % 3)          # borde inferior dentado (dedos)
			for y in range(maxi(top, 0), bot):
				var edge := y == bot - 1 or off % 3 == 0
				img.set_pixel(x, y, wing_d if edge else wing)
	for y in h:                                # cuerpo central peludo
		for x in w:
			var dx := (float(x) - 15.0) / 5.0
			var dy := (float(y) - 11.0) / 7.5
			var d := dx * dx + dy * dy
			if d <= 1.0:
				img.set_pixel(x, y, body_d if d > 0.72 else body)
	for ear in [12, 18]:                       # orejas
		img.set_pixel(ear, 2, body_d)
		img.set_pixel(ear, 3, body)
		img.set_pixel(ear, 4, body)
	for ex in [13, 17]:                        # ojos rojos
		img.set_pixel(ex, 9, Color("ff3b30"))
		img.set_pixel(ex, 10, Color("ffd0c0"))
	for fx in [14, 16]:                        # colmillos
		img.set_pixel(fx, 14, Color("fff0e0"))
	return ImageTexture.create_from_image(img)


## Mega Topo: cuerpo macizo con placas de armadura, hocico rosado, ojos
## furiosos y enormes garras de excavar que sobresalen por debajo.
func _make_boss_mole() -> ImageTexture:
	var w := 26
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var body := Color("8a5a3a")
	var body_d := Color("4a3226")
	var claw := Color("e8e0d0")
	for y in h:
		for x in w:
			var dx := (float(x) - 13.0) / 12.0
			var dy := (float(y) - 11.0) / 8.5
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var c := body_d if d > 0.74 else body
			if (x + y) % 5 == 0 and d < 0.7:    # placas de armadura
				c = body_d
			img.set_pixel(x, y, c)
	for sx in range(11, 16):                    # hocico
		img.set_pixel(sx, 13, Color("e89aa0"))
	img.set_pixel(13, 14, Color("c97a82"))
	for side in [0, 1]:                         # garras gigantes
		var bx := 3 if side == 0 else 22
		for k in 3:
			var gx := bx + (k if side == 0 else -k)
			img.set_pixel(gx, 16, claw)
			img.set_pixel(gx, 17, claw)
			img.set_pixel(gx, 18, claw if k == 1 else claw.darkened(0.2))
	for ex in [10, 16]:                         # ojos furiosos
		img.set_pixel(ex, 8, Color("ff3030"))
	return ImageTexture.create_from_image(img)


## Mega Corredor: bestia robusta con grandes cuernos hacia adelante (frente
## de carga a la izquierda), ojos feroces, músculos marcados y resoplido.
func _make_boss_runner() -> ImageTexture:
	var w := 28
	var h := 18
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var body := Color("e07a30")
	var body_d := Color("a8501c")
	var horn := Color("f0e0c0")
	for y in h:
		for x in w:
			var dx := (float(x) - 14.0) / 13.0
			var dy := (float(y) - 10.0) / 7.5
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			var c := body_d if d > 0.72 else body
			if x < 9 and (x + y) % 3 == 0:      # músculos del frente
				c = body.lightened(0.12)
			img.set_pixel(x, y, c)
	for k in 7:                                 # cuernos hacia adelante
		var hx := 6 - k
		if hx < 0:
			continue
		img.set_pixel(hx, 5 + k / 2, horn)
		img.set_pixel(hx, 11 - k / 2, horn)
	for ex in [9, 13]:                          # ojos feroces
		img.set_pixel(ex, 7, Color("ff2020"))
		img.set_pixel(ex, 8, Color("ffd0a0"))
	img.set_pixel(3, 10, body_d)                # fosas nasales
	img.set_pixel(3, 12, body_d)
	return ImageTexture.create_from_image(img)


## Taladro (Fase 10): dron metálico con un taladro cónico abajo —
## "rompedor vertical" que excava bloques sólidos.
func _make_drill(body: Color, body_d: Color, bit: Color) -> ImageTexture:
	var w := 16
	var h := 14
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(0, 8):
		for x in range(1, 15):
			if (x == 1 or x == 14) and (y == 0 or y == 7):
				continue
			img.set_pixel(x, y, body_d if (x <= 2 or y >= 6) else body)
	for p in [[7, 3], [8, 3], [7, 4], [8, 4]]:
		img.set_pixel(p[0], p[1], Color("ff3030"))
	for y in range(8, h):
		var half := h - y
		var x0 := 8 - half / 2
		for x in range(x0, x0 + half):
			if x < 0 or x >= w:
				continue
			img.set_pixel(x, y, bit.darkened(0.35) if (x + y) % 2 == 0 else bit)
	return ImageTexture.create_from_image(img)


## Topo (Fase 10): cuerpo ovalado con garras de excavar y hocico rosado.
func _make_mole(body: Color, body_d: Color, claw: Color) -> ImageTexture:
	var w := 16
	var h := 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (float(x) - 7.5) / 7.5
			var dy := (float(y) - 6.5) / 5.5
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			img.set_pixel(x, y, body_d if (d > 0.8 or y > 9) else body)
	for cx in [2, 13]:
		for cy in range(8, 11):
			img.set_pixel(cx, cy, claw)
	img.set_pixel(7, 8, Color("e89aa0"))
	img.set_pixel(8, 8, Color("e89aa0"))
	for ex in [5, 10]:
		img.set_pixel(ex, 4, Color("2a1c14"))
	return ImageTexture.create_from_image(img)


## Embistedor (Fase 10): cuerpo robusto con cuernos a ambos lados
## (carga en cualquier dirección) y ojos furiosos.
func _make_charger(body: Color, body_d: Color, horn: Color) -> ImageTexture:
	var w := 22
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (float(x) - 11.0) / 10.0
			var dy := (float(y) - 9.0) / 6.5
			var d := dx * dx + dy * dy
			if d > 1.0:
				continue
			img.set_pixel(x, y, body_d if d > 0.78 else body)
	for side in [0, 1]:
		var base_x := 1 if side == 0 else w - 2
		var dir := 1 if side == 0 else -1
		for k in 4:
			var hx := base_x + dir * k
			var hy := 7 - k
			if hx >= 0 and hx < w and hy >= 0:
				img.set_pixel(hx, hy, horn)
	for ex in [7, 14]:
		img.set_pixel(ex, 5, Color("ff3030"))
	return ImageTexture.create_from_image(img)


## Flecha de la torre (Fase 8): asta de madera + punta de piedra + plumas.
func _make_arrow() -> ImageTexture:
	var img := Image.create(10, 4, false, Image.FORMAT_RGBA8)
	for x in 10:
		img.set_pixel(x, 1, P_LOG)
		img.set_pixel(x, 2, P_LOG_D)
	for x in [8, 9]:
		for y in 4:
			img.set_pixel(x, y, P_SPIKE)
	img.set_pixel(0, 0, P_WALL_L)
	img.set_pixel(0, 3, P_WALL_L)
	return ImageTexture.create_from_image(img)


func _make_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([top, bottom])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 128
	return tex


func _make_cloud() -> ImageTexture:
	var img := Image.create(96, 28, false, Image.FORMAT_RGBA8)
	var blobs := [[24, 16, 12], [40, 12, 14], [58, 14, 13], [74, 17, 10], [48, 18, 16]]
	for y in 28:
		for x in 96:
			for b: Array in blobs:
				var dx := float(x - int(b[0]))
				var dy := float(y - int(b[1])) * 1.6
				var rad := float(b[2])
				if dx * dx + dy * dy < rad * rad and y < 22:
					img.set_pixel(x, y, C_CLOUD)
					break
	return ImageTexture.create_from_image(img)


## Silueta de colinas (1D random-walk suavizado), tileable a lo ancho.
func _make_hills(col: Color, seed_n: int) -> ImageTexture:
	var w := 320
	var h := 80
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var heights := []
	var y := 40.0
	var vel := 0.0
	for x in w:
		vel += (_h(x / 8, 0, seed_n) - 0.5) * 1.6
		vel = clampf(vel, -2.0, 2.0)
		y = clampf(y + vel * 0.5, 14.0, 60.0)
		heights.append(y)
	# fundir extremos para que tilee sin costura
	for x in 24:
		var t := float(x) / 24.0
		heights[x] = lerpf(heights[w - 1], heights[x], t)
	for x in w:
		var top := int(heights[x])
		for yy in range(top, h):
			var c := col if yy > top else col.lightened(0.12)
			img.set_pixel(x, yy, c)
	return ImageTexture.create_from_image(img)
