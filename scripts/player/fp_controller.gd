# fp_controller.gd
# First-person controller for walking the train.
#   WASD move · Shift sprint · Space jump · Ctrl (hold) / C (toggle) crouch · E interact
#   Mouse look · Esc pauses (PauseMenu; without one it frees the mouse, a click recaptures it).
# Interaction: a ray from the camera finds the nearest body or area (layers 1 and 2) and walks up
# its parents to the first node with interact(); get_prompt() on it fills the HUD hint.
# While the train runs (TrainState.speed) the camera sways and bumps over the rail joints.
# Settings (autoload): FOV, mouse sensitivity and invert Y, head bob; camera shake scales the
# train's sway and the scare trauma (add_trauma), which moves the camera only, never the body.
class_name FPController
extends CharacterBody3D

signal footstep(surface: String, strength: float)    # strength 0..1 (crouch soft, sprint hard)
signal jumped
signal landed(fall_speed: float)
signal interacted(target: Node)

@export_group("Movement")
@export var walk_speed: float = 2.6
@export var sprint_speed: float = 5.2
@export var crouch_speed: float = 1.3
@export var ground_accel: float = 14.0
@export var air_accel: float = 2.5
@export var jump_velocity: float = 4.75         # clears about 1.15 m: back up onto a platform from the track
@export var mouse_sensitivity: float = 0.002
@export_group("Crouch")
@export var stand_height: float = 1.75
@export var crouch_height: float = 1.15
@export var stand_eye: float = 1.5
@export var crouch_eye: float = 0.95
@export var crouch_rate: float = 7.0
@export_group("Feel")
@export var bob_amount: float = 0.035
@export var step_length: float = 0.72          # metres per footstep when walking
@export var interact_reach: float = 2.0
@export_group("Shake")
@export var trauma_decay: float = 1.1          # trauma lost per second
@export var shake_offset: float = 0.045        # metres at full trauma
@export var shake_angle: float = 2.2           # degrees of yaw/pitch/roll at full trauma

@onready var _head: Node3D = $Head
@onready var _cam: Camera3D = $Head/Camera
@onready var _col: CollisionShape3D = $Collision

# Registered at runtime so the project's InputMap doesn't need editing.
const KEY_ACTIONS := {
	"fp_forward": [KEY_W, KEY_UP],
	"fp_back": [KEY_S, KEY_DOWN],
	"fp_left": [KEY_A, KEY_LEFT],
	"fp_right": [KEY_D, KEY_RIGHT],
	"fp_jump": [KEY_SPACE],
	"fp_sprint": [KEY_SHIFT],
	"fp_crouch": [KEY_CTRL],
	"fp_crouch_toggle": [KEY_C],
	"fp_interact": [KEY_E],
}
const COYOTE := 0.12
const JUMP_BUFFER := 0.15
const RAIL_LENGTH := 25.0         # metres between rail joints

var crouching := false
var _crouch_t := 0.0              # 0 standing … 1 crouched (eased height)
var _crouch_toggled := false
var _coyote := 0.0
var _jump_buf := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _bob_phase := 0.0
var _step_dist := 0.0
var _time := 0.0
var _joint_kick := 0.0
var _last_joint := -1
var _target: Node = null
var _hud_prompt: Label
var _hud_msg: Label
var _hud_cross: Control
var _msg_time := 0.0
var _focus: Node = null            # a terminal (or anything) the player is sitting at
var _focus_tween: Tween
var _focus_view := Transform3D()
var _focus_settled := false
var _trauma := 0.0                 # 0..1; the shake is trauma², scaled by Settings.camera_shake
var _settings: Node = null
var _pause: PauseMenu

func _ready() -> void:
	_ensure_actions()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(50.0)
	# Own shape so crouching never changes a shared resource.
	_col.shape = _col.shape.duplicate()
	_build_hud()
	_pause = PauseMenu.attach(self)
	_settings = get_node_or_null("/root/Settings")
	if _settings:
		_settings.changed.connect(_on_setting)
		_cam.fov = float(_settings.get("fov"))

func _on_setting(key: String) -> void:
	if key == "fov":
		_cam.fov = float(_settings.get("fov"))

## Shakes the camera (only the camera): add 0.2 for a knock, 0.5 for a slam, 1.0 for a lunge.
## Decays by itself; the player's camera-shake setting scales it (0 turns it off).
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func get_trauma() -> float:
	return _trauma

func _shake_scale() -> float:
	return float(_settings.get("camera_shake")) if _settings else 1.0

func _unhandled_input(event: InputEvent) -> void:
	if _focus != null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		var motion := event as InputEventMouseMotion
		var sens := mouse_sensitivity * (float(_settings.get("mouse_sensitivity")) if _settings else 1.0)
		var inv := -1.0 if _settings and _settings.get("invert_y") else 1.0
		rotate_y(-motion.relative.x * sens)
		_head.rotate_x(-motion.relative.y * sens * inv)
		_head.rotation.x = clampf(_head.rotation.x, -1.5, 1.5)
	elif event.is_action_pressed("ui_cancel") and not is_instance_valid(_pause):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("fp_crouch_toggle"):
		_crouch_toggled = not _crouch_toggled
	elif event.is_action_pressed("fp_interact") and captured:
		_interact()

func _physics_process(delta: float) -> void:
	_time += delta
	if _focus != null:
		# Seated at something: the eye stays exactly where it was put; no walking.
		if _focus_settled:
			_cam.global_transform = _focus_view
		velocity = Vector3(0, velocity.y if not is_on_floor() else 0.0, 0)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	_update_crouch(delta)
	var on_floor := is_on_floor()
	# Jumping, with a little grace after walking off an edge and before landing.
	_coyote = COYOTE if on_floor else maxf(_coyote - delta, 0.0)
	_jump_buf = JUMP_BUFFER if Input.is_action_just_pressed("fp_jump") else maxf(_jump_buf - delta, 0.0)
	if not on_floor:
		velocity += get_gravity() * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	if _jump_buf > 0.0 and _coyote > 0.0 and not crouching:
		velocity.y = jump_velocity
		_jump_buf = 0.0
		_coyote = 0.0
		jumped.emit()

	var input := Input.get_vector("fp_left", "fp_right", "fp_forward", "fp_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0.0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var sprinting := Input.is_action_pressed("fp_sprint") and not crouching and input.y < -0.3
	var speed := crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
	var accel := ground_accel if on_floor else air_accel
	var hv := Vector2(velocity.x, velocity.z).move_toward(Vector2(dir.x, dir.z) * speed, accel * speed * delta)
	velocity.x = hv.x
	velocity.z = hv.y
	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		landed.emit(_fall_speed)
		if _fall_speed > 1.5:
			footstep.emit(_surface(), clampf(_fall_speed / 5.0, 0.4, 1.0))
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()
	_update_steps(delta, sprinting)
	_update_camera(delta)
	_update_target()

# ————— focus (using a terminal) —————

## Moves the eye to `view` (global) and hands the input to `target` until release_focus().
func focus_on(target: Node, view: Transform3D) -> void:
	_focus = target
	_focus_view = view
	_focus_settled = false
	_hud_prompt.get_parent().get_parent().visible = false
	if _focus_tween:
		_focus_tween.kill()
	_focus_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_property(_cam, "global_transform", view, 0.55)
	_focus_tween.tween_callback(func() -> void: _focus_settled = true)

func release_focus() -> void:
	_focus_settled = false
	if _focus_tween:
		_focus_tween.kill()
	_focus_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_property(_cam, "transform", Transform3D.IDENTITY, 0.45)
	_focus_tween.tween_callback(func() -> void:
		_focus = null
		_hud_prompt.get_parent().get_parent().visible = true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_focused() -> bool:
	return _focus != null

# ————— crouch —————

func _update_crouch(delta: float) -> void:
	var want := Input.is_action_pressed("fp_crouch") or _crouch_toggled
	if want:
		crouching = true
	elif crouching and _can_stand():
		crouching = false
	_crouch_t = move_toward(_crouch_t, 1.0 if crouching else 0.0, delta * crouch_rate)
	var e := _crouch_t * _crouch_t * (3.0 - 2.0 * _crouch_t)
	var h := lerpf(stand_height, crouch_height, e)
	var cap := _col.shape as CapsuleShape3D
	if not is_equal_approx(cap.height, h):
		cap.height = h
		_col.position.y = h * 0.5
	_head.position.y = lerpf(stand_eye, crouch_eye, e)

# Room to stand up: the crouched body could move up by the height it would gain.
func _can_stand() -> bool:
	var cap := _col.shape as CapsuleShape3D
	var gain := stand_height - cap.height
	if gain <= 0.01:
		return true
	return not test_move(global_transform, Vector3(0, gain, 0))

# ————— steps, bob and sway —————

func _update_steps(delta: float, sprinting: bool) -> void:
	var hs := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or hs < 0.3:
		_bob_phase = lerpf(_bob_phase, roundf(_bob_phase / PI) * PI, delta * 6.0)
		return
	var stride := step_length * (1.25 if sprinting else (0.7 if crouching else 1.0))
	_bob_phase += hs * delta / stride * PI
	_step_dist += hs * delta
	if _step_dist >= stride:
		_step_dist -= stride
		var strength := 0.35 if crouching else (1.0 if sprinting else 0.65)
		footstep.emit(_surface(), strength)

func _update_camera(delta: float) -> void:
	var hs := Vector2(velocity.x, velocity.z).length()
	var k := clampf(hs / sprint_speed, 0.0, 1.0) if is_on_floor() else 0.0
	var bob := bob_amount if _settings == null or _settings.get("head_bob") else 0.0
	var bob_y := -absf(sin(_bob_phase)) * bob * (0.4 + k)
	var bob_x := sin(_bob_phase) * bob * 0.5 * (0.4 + k)
	var shake := _shake_scale()
	# Train: slow roll and a double knock as each bogie crosses a rail joint.
	var tv := 0.0
	var dist := 0.0
	var ts := get_node_or_null("/root/TrainState")
	if ts:
		tv = float(ts.get("speed"))
		dist = float(ts.get("distance"))
	var tk := clampf(tv / 25.0, 0.0, 1.0)
	var joint := int(floor(dist / RAIL_LENGTH * 2.0))     # two knocks per rail length (bogies)
	if joint != _last_joint:
		if _last_joint >= 0 and tv > 1.0:
			_joint_kick = 0.004 + 0.006 * tk
		_last_joint = joint
	_joint_kick = move_toward(_joint_kick, 0.0, delta * 0.06)
	var roll := deg_to_rad(0.45) * tk * (sin(_time * 1.1) * 0.7 + sin(_time * 2.7 + 1.3) * 0.3) * shake
	var heave := (0.006 * tk * sin(_time * 4.3) - _joint_kick) * shake
	# Trauma: three detuned sines per axis read as noise, strong at first and settling as it decays.
	_trauma = move_toward(_trauma, 0.0, delta * trauma_decay)
	var tr := _trauma * _trauma * shake
	var t := _time * 31.0
	var jx := (sin(t * 1.13) * 0.6 + sin(t * 2.71 + 0.4) * 0.4) * tr
	var jy := (sin(t * 1.37 + 1.9) * 0.6 + sin(t * 2.33 + 2.6) * 0.4) * tr
	var jr := (sin(t * 0.91 + 3.1) * 0.6 + sin(t * 2.07 + 0.8) * 0.4) * tr
	_cam.position = Vector3(bob_x + jx * shake_offset, bob_y + heave + jy * shake_offset, 0)
	_cam.rotation = Vector3(deg_to_rad(jy * shake_angle), deg_to_rad(jx * shake_angle), roll - bob_x * 0.4 + deg_to_rad(jr * shake_angle))

# What the player stands on, for footstep sounds: a "surface" meta on the floor collider or one of
# its parents ("carpet", "wood", "metal", "tile", "snow"…), else "default".
func _surface() -> String:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y < 0.6:
			continue
		var n: Node = c.get_collider() as Node
		while n:
			if n.has_meta("surface"):
				return str(n.get_meta("surface"))
			n = n.get_parent()
	return "default"

# ————— interaction —————

func _update_target() -> void:
	var t := _find_target()
	_target = t
	var prompt := ""
	if t and t.has_method("get_prompt"):
		prompt = str(t.call("get_prompt"))
	_hud_prompt.text = prompt
	_hud_prompt.visible = prompt != ""
	(_hud_cross as Control).modulate = Color(1, 0.85, 0.5, 0.95) if t else Color(1, 1, 1, 0.55)
	if _msg_time > 0.0:
		_msg_time -= get_physics_process_delta_time()
		_hud_msg.modulate.a = clampf(_msg_time, 0.0, 1.0)

func _find_target() -> Node:
	var from := _cam.global_position
	var to := from - _cam.global_basis.z * interact_reach
	var q := PhysicsRayQueryParameters3D.create(from, to, 0b11, [get_rid()])
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var n: Node = hit.collider as Node
	while n and n != self:
		if n.has_method("interact"):
			return n
		n = n.get_parent()
	return null

func _interact() -> void:
	if _target == null:
		return
	var r := str(_target.call("interact", self))
	interacted.emit(_target)
	if r != "":
		show_message(r)

func show_message(text: String, seconds: float = 2.0) -> void:
	_hud_msg.text = text
	_hud_msg.modulate.a = 1.0
	_msg_time = seconds

# ————— HUD —————

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_hud_cross = _Crosshair.new()
	_hud_cross.set_anchors_preset(Control.PRESET_CENTER)
	_hud_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud_cross)
	_hud_prompt = _hud_label(root, 34)
	_hud_msg = _hud_label(root, 64)
	_hud_msg.add_theme_color_override("font_color", Color(1.0, 0.78, 0.6))
	_hud_msg.modulate.a = 0.0

func _hud_label(root: Control, below: float) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = -300
	l.offset_right = 300
	l.offset_top = below
	l.offset_bottom = below + 28
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.96, 0.93, 0.85))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l

class _Crosshair extends Control:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 2.2, Color(0, 0, 0, 0.5))
		draw_circle(Vector2.ZERO, 1.5, Color.WHITE)

func _ensure_actions() -> void:
	for action: String in KEY_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in KEY_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
