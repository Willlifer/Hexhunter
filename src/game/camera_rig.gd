class_name HHCameraRig
extends Node3D
## The orbit camera, from Black | White's BWCameraRig (itself the Temporal Sea
## V8 combat camera), reshaped for a third-person MMO (kickoff: "free-rotating,
## zoomable third-person orbit camera centred on the player, OSRS style").
##   left-drag or middle-drag    orbit (yaw + pitch, pitch 15-80 deg)  (H32: left = look)
##   wheel                        zoom
##   arrow keys                   yaw (left/right) and pitch (up/down)
##   a click without a drag       `clicked(button, screen_pos)` for HHFight (right = act)
##   shake(amount)                a decaying kick on impacts
## The follow lags (a follow camera lags, it does not snap).

signal clicked(button: int, screen_pos: Vector2)

const FOV := 40.0
const PITCH_MIN := 15.0
const PITCH_MAX := 80.0
const DIST_MIN := 5.0
const DIST_MAX := 40.0         ## the fight's clamp (the default of dist_max)
const FOLLOW_LAG := 6.0
const DRAG_THRESHOLD := 3.0
const YAW_PER_PX := 0.008
const PITCH_PER_PX := 0.006
const KEY_YAW := 1.8          # rad/s
const KEY_PITCH := 1.0

var cam: Camera3D
var pivot := Vector3.ZERO: set = _set_pivot
var yaw := deg_to_rad(0.0): set = _set_yaw
var pitch := deg_to_rad(48.0): set = _set_pitch
var dist_max := DIST_MAX      ## L-21 (H761): per instance, so the world map can orbit from 170 m without a scaled parent
var dist := 18.0: set = _set_dist
var input_enabled := true
var pivot_lift := 1.2         # look at the chest, not the feet

var _follow_target := Vector3.ZERO
var _shake := 0.0
var _shake_seed := 0.0
var _press := {}              # button -> press position
var _dragging := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	_update()


func _set_pivot(v: Vector3) -> void:
	pivot = v
	_update()


func _set_yaw(v: float) -> void:
	yaw = v
	_update()


func _set_pitch(v: float) -> void:
	pitch = clampf(v, deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX))
	_update()


func _set_dist(v: float) -> void:
	dist = clampf(v, DIST_MIN, dist_max)
	_update()


func _update() -> void:
	if cam == null:
		return
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.position = pivot + dir * dist
	cam.look_at(pivot, Vector3.UP)
	if _shake > 0.001:
		cam.position += Vector3(sin(_shake_seed * 13.1), cos(_shake_seed * 17.3), sin(_shake_seed * 7.7)) * _shake


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func follow(p: Vector3, snap: bool = false) -> void:
	_follow_target = p + Vector3(0, pivot_lift, 0)
	if snap:
		pivot = _follow_target


func _process(delta: float) -> void:
	if input_enabled:
		var y := 0.0
		var p := 0.0
		if Input.is_key_pressed(KEY_LEFT):
			y += 1.0
		if Input.is_key_pressed(KEY_RIGHT):
			y -= 1.0
		if Input.is_key_pressed(KEY_UP):
			p += 1.0
		if Input.is_key_pressed(KEY_DOWN):
			p -= 1.0
		if y != 0.0:
			yaw += y * KEY_YAW * delta
		if p != 0.0:
			pitch += p * KEY_PITCH * delta
	if pivot.distance_to(_follow_target) > 0.002:
		pivot = pivot.lerp(_follow_target, 1.0 - exp(-FOLLOW_LAG * delta))
	if _shake > 0.001:
		_shake *= exp(-9.0 * delta)
		_shake_seed += delta * 60.0
		_update()


func _unhandled_input(ev: InputEvent) -> void:
	if not input_enabled:
		return
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if ev.pressed:
					dist *= 0.9
			MOUSE_BUTTON_WHEEL_DOWN:
				if ev.pressed:
					dist /= 0.9
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if ev.pressed:
					_press[ev.button_index] = ev.position
					_dragging = false
				else:
					if _press.has(ev.button_index) and not _dragging:
						clicked.emit(ev.button_index, ev.position)
					_press.erase(ev.button_index)
					_dragging = false
	elif ev is InputEventMouseMotion:
		var orbit: bool = (ev.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_LEFT)) != 0
		if orbit:
			var start: Vector2 = _press.get(MOUSE_BUTTON_MIDDLE, _press.get(MOUSE_BUTTON_LEFT, ev.position))
			if _dragging or ev.position.distance_to(start) > DRAG_THRESHOLD:
				_dragging = true
				yaw -= ev.relative.x * YAW_PER_PX
				pitch += ev.relative.y * PITCH_PER_PX


## A ray from the camera through a screen point: [origin, direction].
func ray(screen_pos: Vector2) -> Array:
	return [cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos)]
