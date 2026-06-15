# =============================================================
# game_modes.gd — CAPA DE REGLAS (ver ARQUITECTURA.md)
# Definiciones DATA-DRIVEN de los modos de juego. main.gd (el
# orquestador) lee el modo activo de aquí en vez de constantes
# hardcodeadas: añadir un modo nuevo (o una campaña, Fase 11+)
# es añadir una entrada a MODES — el lobby lo muestra solo y el
# reloj/oleadas/recompensas lo obedecen sin tocar más código.
#
# Claves de cada modo:
#   nombre/icono/desc     — presentación en el lobby (capa 3 los lee)
#   day_seconds           — duración del día
#   night_seconds         — duración de la noche
#   nights_to_win         — noches para ganar (0 = sin fin, no hay victoria)
#   death_ends_run        — morir termina la run (sin respawn)
#   save_allowed          — el modo escribe/usa el save del sandbox
#   boss_every            — cada cuántas noches llega el jefe de la run
#   wave_base/wave_step   — enemigos por oleada: base + step * noche
#   night_reward_base/step— Núcleos al amanecer: base + step * noche
#   victory_bonus         — Núcleos extra al ganar
#   meteors               — si caen meteoros de día
#
# REGLA: esta capa es SOLO datos + helpers puros. Nada de nodos,
# red ni UI — eso vive en las otras capas (GDD §16 intacto: el
# servidor sigue siendo quien aplica estas reglas).
# =============================================================
extends RefCounted

const MODES := {
	"survival": {
		"nombre": "Supervivencia", "icono": "🌙",
		"desc": "Sobrevive 7 noches. Morir de noche termina la run.",
		"day_seconds": 180.0, "night_seconds": 90.0,
		"nights_to_win": 7, "death_ends_run": true, "save_allowed": false,
		"boss_every": 5, "wave_base": 3, "wave_step": 1,
		"night_reward_base": 10, "night_reward_step": 5,
		"victory_bonus": 100, "meteors": true,
	},
	"asedio": {
		"nombre": "Asedio", "icono": "⚔️",
		"desc": "3 noches brutales, días cortos. El jefe llega la última noche.",
		"day_seconds": 120.0, "night_seconds": 110.0,
		"nights_to_win": 3, "death_ends_run": true, "save_allowed": false,
		"boss_every": 3, "wave_base": 6, "wave_step": 2,
		"night_reward_base": 25, "night_reward_step": 10,
		"victory_bonus": 150, "meteors": true,
	},
	"sandbox": {
		"nombre": "Sandbox libre", "icono": "🏖️",
		"desc": "Construye sin objetivo. Tu mundo se guarda.",
		"day_seconds": 180.0, "night_seconds": 90.0,
		"nights_to_win": 0, "death_ends_run": false, "save_allowed": true,
		"boss_every": 5, "wave_base": 3, "wave_step": 1,
		"night_reward_base": 10, "night_reward_step": 5,
		"victory_bonus": 0, "meteors": true,
	},
}

# Orden de aparición en el lobby (la capa de presentación lo recorre).
const LOBBY_ORDER := ["survival", "asedio", "sandbox"]


static func get_mode(id: String) -> Dictionary:
	return MODES.get(id, MODES["sandbox"])
