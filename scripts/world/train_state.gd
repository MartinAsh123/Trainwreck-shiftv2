extends Node
## Autoload "TrainState": the one source of truth for the train's motion. The journey controller
## writes it every physics frame; doors, the player's sway, the locomotive's wheels, the world
## scroller and the sounds read it.

signal arrived(station: String)
signal departing(station: String)
signal phase_changed(phase: String)

## Metres travelled along the route since the start of the run.
var distance: float = 0.0
## Current speed, metres per second (never negative).
var speed: float = 0.0
## "stopped", "departing", "running", "braking"
var phase: String = "stopped"
## Station the train is standing at ("" between stations).
var station: String = ""
## Next stop and the distance left to it (metres).
var next_stop: String = ""
var to_next_stop: float = 0.0
## Time of day in hours (19.5 = half past seven in the evening), kept by the Journey.
var clock: float = 19.0

func is_moving() -> bool:
	return speed > 0.25

func set_phase(p: String) -> void:
	if p == phase:
		return
	phase = p
	phase_changed.emit(p)
