class_name ComputerTerminal
extends Node3D
## A staff terminal: the XPDesktop rendered into a SubViewport and shown on the monitor's glass.
## Press E at it to sit in: the camera moves to face the screen, the mouse and keyboard go to the
## desktop (the pointer is the desktop's own), and Esc gets up again.
## Placed by the car builder on the monitor; local -Z faces the room, origin = screen centre.

signal used(active: bool)
signal sound(kind: String)

const CRT := preload("res://shaders/train/crt_screen.gdshader")

@export var screen_size: Vector2 = Vector2(0.435, 0.326)
@export var resolution: Vector2i = Vector2i(1024, 768)
## How far from the glass the eye sits while using it.
@export var view_distance: float = 0.27

var desktop: XPDesktop
var _vp: SubViewport
var _quad: MeshInstance3D
var _user: Node = null
var fault: Node = null               # a breakdown's owner (HauntDirector) while the terminal is dead

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("interactable")
	add_to_group("terminal")
	_vp = SubViewport.new()
	_vp.name = "Screen"
	_vp.size = resolution
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.handle_input_locally = true
	_vp.gui_embed_subwindows = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	desktop = XPDesktop.new()
	desktop.name = "Desktop"
	_vp.add_child(desktop)
	desktop.sound.connect(func(k: String) -> void: sound.emit(k))
	_quad = MeshInstance3D.new()
	_quad.name = "Glass"
	var qm := QuadMesh.new()
	qm.size = screen_size
	_quad.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = CRT
	mat.set_shader_parameter("screen_tex", _vp.get_texture())
	_quad.material_override = mat
	_quad.rotation.y = PI          # face -Z (the room)
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	# A faint glow on the niche from the tube.
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.55, 0.7, 1.0)
	glow.light_energy = 0.25
	glow.omni_range = 1.2
	glow.position = Vector3(0, 0, -0.25)
	glow.shadow_enabled = false
	add_child(glow)
	var area := Area3D.new()
	area.name = "UseArea"
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(screen_size.x + 0.08, screen_size.y + 0.08, 0.06)
	cs.shape = bs
	cs.position = Vector3(0, 0, -0.03)
	area.add_child(cs)
	add_child(area)

# The screen's picture only renders when it can be seen: every frame while in use, once a second
# when someone nearby can see it, not at all otherwise (it keeps its last picture).
var _tick := 0.0

func _process(delta: float) -> void:
	if _vp == null:
		return
	var in_use := _user != null
	desktop.live = in_use
	if in_use:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	var cam := get_viewport().get_camera_3d()
	var seen := cam != null and cam.global_position.distance_to(global_position) < 8.0 			and cam.is_position_in_frustum(global_position)
	if not seen:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_tick = 1.0                      # (render straight away when it comes into view)
		return
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func get_prompt() -> String:
	if fault:
		return str(fault.call("terminal_prompt"))
	return "E — Use terminal"

## Dead (a disk error on the screen) or working again; `set_progress` shows a reinstall going.
func set_broken(on: bool) -> void:
	if on and _user:
		release()
	desktop.set_broken(on)
	_tick = 1.0

func set_progress(k: float) -> void:
	desktop.install_progress = k

func interact(by: Node = null) -> String:
	if fault:
		return str(fault.call("terminal_use"))
	if by and by.has_method("focus_on"):
		_user = by
		by.call("focus_on", self, view_transform())
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		used.emit(true)
	return ""

## Where the eye goes while using the terminal: straight in front of the screen.
func view_transform() -> Transform3D:
	var front := -global_basis.z
	var eye := global_position + front * view_distance
	return Transform3D(Basis.looking_at(-front, global_basis.y), eye)

func release() -> void:
	if _user and _user.has_method("release_focus"):
		_user.call("release_focus")
	_user = null
	used.emit(false)

func _input(event: InputEvent) -> void:
	if _user == null:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		release()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		sound.emit("mouse")
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		sound.emit("key")
	if event is InputEventMouse:
		var uv := _screen_uv((event as InputEventMouse).position)
		var e := event.duplicate() as InputEventMouse
		var p := Vector2(uv.x * resolution.x, uv.y * resolution.y)
		e.position = p
		e.global_position = p
		if e is InputEventMouseMotion:
			var mm := e as InputEventMouseMotion
			mm.relative = mm.relative * float(resolution.y) / get_viewport().get_visible_rect().size.y * 1.15
		_vp.push_input(e, true)
	else:
		_vp.push_input(event, true)
	get_viewport().set_input_as_handled()

# Where the window-space point `p` lands on the screen (0..1, clamped to the glass).
func _screen_uv(p: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(0.5, 0.5)
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	var n := global_basis.z
	var denom := d.dot(n)
	if absf(denom) < 1e-5:
		return Vector2(0.5, 0.5)
	var t := (global_position - o).dot(n) / denom
	var hit := o + d * t
	var l := _quad.global_transform.affine_inverse() * hit
	return Vector2(clampf(l.x / screen_size.x + 0.5, 0.0, 1.0), clampf(0.5 - l.y / screen_size.y, 0.0, 1.0))
