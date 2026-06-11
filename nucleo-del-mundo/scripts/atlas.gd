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

# ---- API pública (llenada en _ready) ----
var tiles: Dictionary = {}     # tipo -> Array[ImageTexture] (variantes)
var grass: Array = []          # variantes de tierra con césped encima
var deco: Array = []           # decoración de superficie: hierba alta y flores
var cracks: Array = []         # 3 overlays de grietas (leve → grave)
var avg: Dictionary = {}       # tipo -> Color promedio (para partículas)
var player_frames: Dictionary = {}  # "idle"/"walk"/"jump" -> Array[{outline, base, shirt}]
var slimes: Dictionary = {}    # variante ("normal"/"grande"/"dorado") -> ImageTexture
var sky_tex: GradientTexture2D
var under_tex: GradientTexture2D
var cloud_tex: ImageTexture
var hill_far_tex: ImageTexture
var hill_near_tex: ImageTexture


func _ready() -> void:
	for t in [T_DIRT, T_STONE, T_ORE, T_BEDROCK, T_WOOD, T_LEAF]:
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
	# Variantes de NPC (npc_manager.KINDS): slimes con otra paleta
	# + el murciélago nocturno (Fase 6)
	slimes["normal"] = _make_slime(Color("3fae4a"), Color("2c8338"), Color("8fe093"))
	slimes["grande"] = _make_slime(Color("8a4ad0"), Color("5c2f96"), Color("c9a0f0"))
	slimes["dorado"] = _make_slime(P_GOLD, P_GOLD_D, P_GOLD_L)
	slimes["murcielago"] = _make_bat()
	sky_tex = _make_gradient(C_SKY_TOP, C_SKY_BOT)
	under_tex = _make_gradient(C_UNDER_TOP, C_UNDER_BOT)
	cloud_tex = _make_cloud()
	hill_far_tex = _make_hills(C_HILL_FAR, 11)
	hill_near_tex = _make_hills(C_HILL_NEAR, 23)


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
		T_DIRT, T_STONE, T_ORE, T_LEAF:
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
func _build_frame(rows: Array) -> Dictionary:
	var base := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	var shirt := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	var outline := Image.create(12, 22, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		var row: String = rows[y]
		for x in 12:
			match row[x]:
				"O": outline.set_pixel(x, y, Color.WHITE)
				"S": base.set_pixel(x, y, C_SKIN)
				"H": base.set_pixel(x, y, C_HAIR)
				"E": base.set_pixel(x, y, C_EYE)
				"P": base.set_pixel(x, y, C_PANTS)
				"p": base.set_pixel(x, y, C_PANTS_D)
				"F": base.set_pixel(x, y, C_BOOT)
				"B": shirt.set_pixel(x, y, Color.WHITE)
				"b": shirt.set_pixel(x, y, Color(0.78, 0.78, 0.78))
	return {"outline": ImageTexture.create_from_image(outline),
		"base": ImageTexture.create_from_image(base),
		"shirt": ImageTexture.create_from_image(shirt)}


func _mirror(rows: Array) -> Array:
	var out := []
	for r: String in rows:
		out.append(r.reverse())
	return out


# -------------------------------------------------------------
# SLIME, CIELO, NUBES Y COLINAS
# -------------------------------------------------------------
func _make_slime(body: Color, body_d: Color, shine: Color) -> ImageTexture:
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
	# ojos
	for ex in [5, 10]:
		img.set_pixel(ex, 5, Color.WHITE)
		img.set_pixel(ex, 6, Color.WHITE)
		img.set_pixel(ex, 6, Color("1c1c24"))
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
