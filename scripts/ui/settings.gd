extends Node
## The player's settings (autoload "Settings"), saved to user://settings.cfg. Every value is a plain
## property; change one with set_value(key, v), which applies it, saves and emits `changed(key)`.
## Other systems read the properties when they need them and listen to `changed` for live updates:
##   Settings.fov · Settings.camera_shake (0..1) · Settings.flash_scale() · Settings.jumpscare
##   Settings.changed.connect(func(key: String) -> void: ...)
## Volumes are 0..1 per audio bus (gain = v², a bus that doesn't exist yet is skipped). The window
## (resolution, fullscreen, vsync) is only touched once the player has changed it, so command-line
## sizes used by the tests keep working.

signal changed(key: String)

const PATH := "user://settings.cfg"
## Volume key -> audio bus name.
const BUSES := {
	"master_volume": "Master", "music_volume": "Music", "sfx_volume": "SFX",
	"ambience_volume": "Ambience", "voice_volume": "Voice", "ui_volume": "UI",
}
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const SUBTITLE_SIZES := {"Small": 20, "Medium": 24, "Large": 32, "Huge": 40}
const DISPLAY_KEYS := ["resolution", "fullscreen", "vsync"]

enum Jumpscare { FULL, SOFT, OFF }

var master_volume := 1.0
var music_volume := 1.0
var sfx_volume := 1.0
var ambience_volume := 1.0
var voice_volume := 1.0
var ui_volume := 1.0
var mouse_sensitivity := 1.0          # multiplier on the controller's base sensitivity (0.2..3)
var invert_y := false
var fov := 75.0                       # 70..100
var head_bob := true
var camera_shake := 1.0               # 0..1: scare trauma and the train's sway and rail knocks
var reduced_flashes := false
var jumpscare := Jumpscare.FULL
var subtitle_size := 24
var resolution := Vector2i(1920, 1080)
var fullscreen := false
var vsync := true

var _display_set := false             # the player has chosen a window setting at least once

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	apply_audio()
	if _display_set:
		apply_display()

## Sets one setting by its property name, applies it, saves and emits `changed`.
func set_value(key: String, value: Variant) -> void:
	if not key in self or get(key) == value:
		return
	set(key, value)
	if BUSES.has(key):
		_apply_bus(key)
	elif key in DISPLAY_KEYS:
		_display_set = true
		apply_display()
	save()
	changed.emit(key)

## How strong a lamp flicker, flash or lightning may be: 1 normally, 0.25 with reduced flashes.
func flash_scale() -> float:
	return 0.25 if reduced_flashes else 1.0

## Extra gain for a jumpscare stinger: 0 dB full, -9 dB soft, silent when jumpscares are off.
func stinger_db() -> float:
	return [0.0, -9.0, -80.0][jumpscare]

## True when a lunge into the face may play at all (soft and full); off means fade instead of lunge.
func lunges_allowed() -> bool:
	return jumpscare != Jumpscare.OFF

func apply_audio() -> void:
	for key: String in BUSES:
		_apply_bus(key)

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(resolution)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(screen.position + (screen.size - resolution) / 2)

func _apply_bus(key: String) -> void:
	var idx := AudioServer.get_bus_index(BUSES[key])
	if idx < 0:
		return
	var v := clampf(float(get(key)), 0.0, 1.0)
	AudioServer.set_bus_volume_linear(idx, v * v)
	AudioServer.set_bus_mute(idx, v <= 0.001)

func save() -> void:
	var cfg := ConfigFile.new()
	for p: Dictionary in _keys():
		var section := "display" if p.name in DISPLAY_KEYS else "settings"
		if section == "display" and not _display_set:
			continue
		cfg.set_value(section, p.name, get(p.name))
	cfg.save(PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for p: Dictionary in _keys():
		var section := "display" if p.name in DISPLAY_KEYS else "settings"
		if cfg.has_section_key(section, p.name):
			var v: Variant = cfg.get_value(section, p.name)
			if typeof(v) == typeof(get(p.name)):
				set(p.name, v)
	_display_set = cfg.has_section("display")
	fov = clampf(fov, 70.0, 100.0)
	camera_shake = clampf(camera_shake, 0.0, 1.0)
	jumpscare = clampi(jumpscare, 0, 2) as Jumpscare

# The saved properties: this script's own variables, except the private ones.
func _keys() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in get_script().get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not str(p.name).begins_with("_"):
			out.append(p)
	return out
