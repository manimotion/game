# =============================================================
# sfx.gd — Autoload "Sfx" (roadmap Fase 5: sonido y música)
# Efectos de sonido Y música de fondo procedurales generados por
# código al arrancar (sin archivos de audio, igual que el arte).
# La música es una pieza suave en loop: progresión Am–F–C–G con
# bajo, acordes tenues y melodía pentatónica de La menor.
# El sonido es 100% local y cosmético: nunca viaja por red ni
# toca estado del juego — la autoridad del servidor (GDD §16)
# queda intacta. En headless (tests/servidor) no se genera música.
# =============================================================
extends Node

const SAMPLE_RATE := 22050
const MUSIC_RATE := 11025      # la música usa menos muestreo (genera más rápido)
const MUSIC_DB := -9.0         # volumen de fondo, por debajo de los SFX
const VOICES := 6              # reproductores en paralelo (round-robin)

var _streams: Dictionary = {}
var _players: Array = []
var _next := 0
var music: AudioStreamPlayer = null


func _ready() -> void:
	# nombre -> barrido de frecuencia (inicio→fin), duración, volumen, ruido
	_streams["golpe"] = _make(180.0, 90.0, 0.07, 0.5, true)      # picar tile/slime
	_streams["poner"] = _make(300.0, 480.0, 0.08, 0.4, false)    # colocar bloque
	_streams["dano"] = _make(220.0, 70.0, 0.25, 0.6, true)       # recibir daño
	_streams["moneda"] = _make(880.0, 1320.0, 0.12, 0.35, false) # ganar Núcleos
	_streams["compra"] = _make(523.0, 1046.0, 0.30, 0.4, false)  # comprar skin
	_streams["meteoro"] = _make(160.0, 40.0, 0.8, 0.6, true)     # evento meteoro
	_streams["fabricar"] = _make(392.0, 784.0, 0.20, 0.42, false) # craftear receta (GDD §8)
	_streams["invasion"] = _make(140.0, 55.0, 0.45, 0.55, true)   # evento invasión de slimes
	# Fases 7-9 (pulido): defensa activa, jefe y estructura de run
	_streams["flecha"] = _make(900.0, 350.0, 0.07, 0.32, true)    # torre dispara
	_streams["pinchos"] = _make(1200.0, 250.0, 0.09, 0.38, true)  # trampa de pinchos
	_streams["jefe"] = _make(70.0, 38.0, 1.0, 0.6, true)          # rugido del jefe
	_streams["noche"] = _make(220.0, 110.0, 0.6, 0.4, false)      # cae la noche
	_streams["amanecer"] = _make(660.0, 990.0, 0.35, 0.3, false)  # amanece
	_streams["victoria"] = _make_jingle([523.25, 659.25, 783.99, 1046.5], 0.16, 0.4)  # C E G C
	_streams["derrota"] = _make_jingle([392.0, 329.63, 261.63, 196.0], 0.22, 0.4)     # G E C G desc.
	# Fase 10: enemigos especiales (taladro, embestidor, nidos)
	_streams["embestida"] = _make(80.0, 320.0, 0.18, 0.55, true)  # carga del embistedor
	_streams["fusion"] = _make(180.0, 540.0, 0.22, 0.45, false)   # dos slimes se fusionan
	_streams["nido"] = _make(95.0, 50.0, 0.5, 0.5, true)          # un nido aparece/palpita
	# Bloque 1 "Mundo vivo": chapoteo al entrar al agua de los ríos profundos
	_streams["agua"] = _make(1400.0, 350.0, 0.10, 0.30, true)
	# Bloque 5 "Identidad visual y sonora": botín y eventos de exploración
	_streams["cofre"] = _make_jingle([659.25, 783.99, 1046.5], 0.10, 0.42)   # cofre/botín: arpegio que sube
	_streams["cura"] = _make_jingle([783.99, 987.77, 1318.5], 0.09, 0.30)    # calavera vital / sanación: brillo suave
	_streams["maldicion"] = _make(330.0, 70.0, 0.5, 0.55, true)              # calavera mala: presagio grave
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	# Música de fondo (no en headless: tests y servidor dedicado)
	if DisplayServer.get_name() != "headless":
		music = AudioStreamPlayer.new()
		music.stream = _make_music()
		music.volume_db = MUSIC_DB
		add_child(music)
		music.play()


func play(nombre: String) -> void:
	if _players.is_empty() or not _streams.has(nombre):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[nombre]
	p.play()


# -------------------------------------------------------------
# MÚSICA: pieza suave en loop (~25 s) compuesta por código.
# 8 compases a 76 BPM: bajo (raíz), acorde tenue y melodía
# pentatónica de La menor sobre Am – F – C – G (x2).
# -------------------------------------------------------------
func _make_music() -> AudioStreamWAV:
	var beat := 60.0 / 76.0            # negra a 76 BPM
	var bar := beat * 4.0
	var bars := 8
	var total := int(MUSIC_RATE * bar * bars)
	var buf := PackedFloat32Array()
	buf.resize(total)

	var roots := [110.0, 87.31, 130.81, 98.0]       # A2  F2  C3  G2
	var chords := [
		[220.0, 261.63, 329.63],                     # Am: A3 C4 E4
		[174.61, 220.0, 261.63],                     # F:  F3 A3 C4
		[196.0, 261.63, 329.63],                     # C/G: G3 C4 E4
		[196.0, 246.94, 293.66],                     # G:  G3 B3 D4
	]
	# Melodía: 4 negras por compás (0 = silencio), pentatónica de Am
	var mel := [
		[440.0, 0.0, 523.25, 440.0],
		[392.0, 329.63, 0.0, 293.66],
		[329.63, 392.0, 440.0, 0.0],
		[293.66, 0.0, 329.63, 392.0],
		[523.25, 0.0, 440.0, 392.0],
		[440.0, 392.0, 329.63, 0.0],
		[392.0, 0.0, 329.63, 293.66],
		[329.63, 293.66, 0.0, 0.0],
	]

	for b in bars:
		var t0 := b * bar
		var ch: Array = chords[b % 4]
		_note(buf, t0, bar * 0.95, roots[b % 4], 0.16)            # bajo
		for f: float in ch:                                        # acorde tenue
			_note(buf, t0, bar, f, 0.06)
		for q in 4:                                                # melodía
			var f2: float = mel[b][q]
			if f2 > 0.0:
				_note(buf, t0 + q * beat, beat * 0.9, f2, 0.13)

	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MUSIC_RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = total
	return w


## Suma una nota senoidal (con un armónico suave) al buffer:
## ataque corto y caída lenta para un timbre tipo "pad" tranquilo.
func _note(buf: PackedFloat32Array, start_s: float, dur_s: float, freq: float, vol: float) -> void:
	var s0 := int(start_s * MUSIC_RATE)
	var n := int(dur_s * MUSIC_RATE)
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			return
		var t := float(i) / float(n)
		var env := minf(t / 0.12, 1.0) * (1.0 - t)
		var ph := TAU * freq * float(i) / MUSIC_RATE
		buf[idx] += (sin(ph) + 0.35 * sin(ph * 2.0)) * env * vol


## Jingle: secuencia de notas senoidales (con armónico) una tras otra.
## Para victoria/derrota — más musical que un barrido (Fase 9, pulido).
func _make_jingle(freqs: Array, note_dur: float, vol: float) -> AudioStreamWAV:
	var per := int(SAMPLE_RATE * note_dur)
	var n := per * freqs.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for k in freqs.size():
		var f: float = freqs[k]
		for i in per:
			var t := float(i) / float(per)
			var env := minf(t / 0.08, 1.0) * (1.0 - t * 0.85)
			var ph := TAU * f * float(i) / SAMPLE_RATE
			var s := (sin(ph) + 0.3 * sin(ph * 2.0)) * env * vol
			data.encode_s16((k * per + i) * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SAMPLE_RATE
	w.data = data
	return w


## Sintetiza un tono con barrido de frecuencia y envolvente decreciente.
## Con ruido=true se mezcla ruido blanco (golpes, explosiones).
func _make(f0: float, f1: float, dur: float, vol: float, ruido: bool) -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var fase := 0.0
	for i in n:
		var t := float(i) / float(n)
		fase += TAU * lerpf(f0, f1, t) / SAMPLE_RATE
		var s := sin(fase)
		if ruido:
			s = s * 0.35 + randf_range(-0.65, 0.65)
		var v := int(clampf(s * (1.0 - t) * vol, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SAMPLE_RATE
	w.data = data
	return w
