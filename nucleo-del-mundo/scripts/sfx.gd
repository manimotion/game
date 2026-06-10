# =============================================================
# sfx.gd — Autoload "Sfx" (roadmap Fase 5: sonido)
# Efectos de sonido procedurales generados por código al arrancar
# (sin archivos de audio, igual que el arte por draw_rect).
# El sonido es 100% local y cosmético: nunca viaja por red ni
# toca estado del juego — la autoridad del servidor (GDD §16)
# queda intacta.
# =============================================================
extends Node

const SAMPLE_RATE := 22050
const VOICES := 6              # reproductores en paralelo (round-robin)

var _streams: Dictionary = {}
var _players: Array = []
var _next := 0


func _ready() -> void:
	# nombre -> barrido de frecuencia (inicio→fin), duración, volumen, ruido
	_streams["golpe"] = _make(180.0, 90.0, 0.07, 0.5, true)      # picar tile/slime
	_streams["poner"] = _make(300.0, 480.0, 0.08, 0.4, false)    # colocar bloque
	_streams["dano"] = _make(220.0, 70.0, 0.25, 0.6, true)       # recibir daño
	_streams["moneda"] = _make(880.0, 1320.0, 0.12, 0.35, false) # ganar Núcleos
	_streams["compra"] = _make(523.0, 1046.0, 0.30, 0.4, false)  # comprar skin
	_streams["meteoro"] = _make(160.0, 40.0, 0.8, 0.6, true)     # evento meteoro
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(nombre: String) -> void:
	if _players.is_empty() or not _streams.has(nombre):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[nombre]
	p.play()


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
