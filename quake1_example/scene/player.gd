extends CharacterBody3D
class_name QmapbspQuakePlayer

# THESE VALUES WERE APPROXIMATELY MEASURED
# TO MATCH AN ORIGINAL AS CLOSE AS POSSIBLE >/\<

# my definition is 32 units/1 meter

var viewer : QmapbspQuakeViewer

@export var max_speed : float = 10
@export var max_air_speed : float = 0.5
@export var accel : float = 100
@export var fric : float = 8
@export var sensitivity : float = 0.0025
@export var stairstep := 0.6
@export var stairstep_down := 0.6
@export var stairstep_deg := deg_to_rad(20.0)
@export var gravity : float = 20
@export var jump_up : float = 7.6

var noclip : bool = false

@onready var around : Node3D = $around
@onready var head : Node3D = $around/head
@onready var camera : Camera3D = $around/head/cam
#@onready var staircast : ShapeCast3D = $staircast
@onready var jump : AudioStreamPlayer3D = $jump
@onready var origin : Node3D = $origin

var wishdir : Vector3
var wish_jump : bool = false
var auto_jump : bool = true
var smooth_y : float

var fluid : QmapbspQuakeFluidVolume

var tbodyq : PhysicsTestMotionParameters3D
var tbodyr : PhysicsTestMotionResult3D

func _ready() :
	jump.stream = viewer.hub.load_audio("player/plyrjmp8.wav")
	tbodyq = PhysicsTestMotionParameters3D.new()
	tbodyr = PhysicsTestMotionResult3D.new()

func teleport_to(dest : Node3D, play_sound : bool = false) :
	global_position = dest.global_position
	var old := around.rotation
	around.rotation = dest.rotation
	old = around.rotation - old
	velocity = velocity.rotated(Vector3.UP, old.y)
	if play_sound :
		var p := AudioStreamPlayer3D.new()
		p.stream = (
			viewer.hub.load_audio('misc/r_tele%d.wav' % (randi() % 5 + 1))
		)
		
		p.finished.connect(func() :
			p.queue_free()
			)
		viewer.add_child(p)
		p.global_position = global_position
		p.play()
		

func accelerate(in_speed : float, delta : float) -> void :
	velocity += wishdir * (
		clampf(in_speed - velocity.dot(wishdir), 0, accel * delta)
	)

func friction(delta : float) -> void :
	var speed : float = velocity.length()
	var svec : Vector3
	if speed > 0 :
		svec = velocity * maxf(speed - (
			fric * speed * delta
		), 0) / speed
	if speed < 0.1 :
		svec = Vector3()
	velocity = svec

func move_ground(delta : float) -> void :
	friction(delta)
	accelerate(max_speed, delta)
	
	#_stairs(delta)
	
	move_and_slide()
	_coltest()
	
	_process_stair(delta)
	
#func _stairs(delta : float) :
	#var w := (velocity / max_speed) * Vector3(2.0, 0.0, 2.0) * delta
	#var ws := w * max_speed
	#
	## stair stuffs
	#var shape : BoxShape3D = staircast.shape
	#shape.size = Vector3(
		#1.0 + ws.length(), shape.size.y, 1.0 + ws.length()
	#)
	#
	#staircast.position = Vector3(
		#ws.x, 0.175 + stairstep - 0.75, ws.z
	#)

func move_air(delta : float) -> void :
	accelerate(max_air_speed, delta)
	#_stairs(delta)
	move_and_slide()
	_coltest()
	_process_stair(delta)
	
func move_noclip(delta : float) -> void :
	friction(delta)
	accelerate(max_speed, delta)
	translate(velocity * delta)
	_watercoltest()
	
func _process_stair(delta : float) -> void :
	var delta_motion := velocity * delta
	delta_motion.y = 0.0
	
	if (delta_motion + wishdir).is_zero_approx() :
		return
	
	var delta_motion_up := delta_motion + wishdir * 0.1
	
	# check objects above the character
	tbodyq.from = global_transform
	tbodyq.motion = Vector3(0, stairstep, 0)
	if PhysicsServer3D.body_test_motion(
		get_rid(), tbodyq, tbodyr
	) :
		return
		
	# check objects on the front
	tbodyq.from.origin.y += stairstep
	tbodyq.motion = delta_motion_up
	if PhysicsServer3D.body_test_motion(
		get_rid(), tbodyq, tbodyr
	) :
		# this fixes movement stuck if the character is trying to move diagonally
		delta_motion_up = delta_motion_up.slide(tbodyr.get_collision_normal())
		#return
		
	# check objects below
	tbodyq.from.origin += delta_motion_up
	# 0.001 is a bonus motion addition for godot physics. won't do anything in jolt physics
	tbodyq.motion = Vector3(0, -stairstep+0.001, 0)
	if PhysicsServer3D.body_test_motion(
		get_rid(), tbodyq, tbodyr
	) :
		if (
			tbodyr.get_collision_normal().angle_to(Vector3.UP)
			<=
			stairstep_deg
		) :
			var height := -tbodyr.get_remainder().y
			position.y += height + 0.01
			smooth_y = -height
			around.position.y += smooth_y
			return
			
	
			
	# trying to snap to the ground if moving off stairs
	if wish_jump or !is_on_floor() :
		return
	
	# check objects on the front
	tbodyq.from = global_transform
	tbodyq.motion = delta_motion
	if PhysicsServer3D.body_test_motion(
		get_rid(), tbodyq, tbodyr
	) :
		delta_motion_up = delta_motion_up.slide(tbodyr.get_collision_normal())
		
	# check objects below
	tbodyq.from.origin += delta_motion
	tbodyq.motion = Vector3(0, -stairstep_down, 0)
	if PhysicsServer3D.body_test_motion(
		get_rid(), tbodyq, tbodyr
	) :
		if (
			tbodyr.get_travel().y < -stairstep_down and
			tbodyr.get_collision_normal().angle_to(Vector3.UP)
			<=
			stairstep_deg
		) :
			var height := tbodyr.get_travel().y
			position.y += height
			smooth_y = -height
			around.position.y += smooth_y

func _physics_process(delta : float) -> void :
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED :
		return
		
	wishdir = (head if noclip else around).global_transform.basis * Vector3((
		Input.get_axis(&"q1_move_left", &"q1_move_right")
	), 0, (
		Input.get_axis(&"q1_move_forward", &"q1_move_back")
	)).normalized()
	
	if noclip :
		move_noclip(delta)
		return
	
	if auto_jump :
		wish_jump = Input.is_action_pressed(&"q1_jump")
	else :
		if !wish_jump and Input.is_action_just_pressed(&"q1_jump") :
			wish_jump = true
		if Input.is_action_just_released(&"q1_jump") :
			wish_jump = false
	
	if fluid :
		# trash movement ;)
		if wish_jump :
			velocity.y = jump_up
			move_air(delta)
		else :
			if is_on_floor() :
				velocity.y = 0
				move_ground(delta)
			else :
				velocity.y -= gravity * delta * 0.25
				move_air(delta)
			
	else :
		if is_on_floor() :
			if wish_jump :
				jump.play()
				velocity.y = jump_up
				move_air(delta)
				wish_jump = false
			else :
				velocity.y = 0
				move_ground(delta)
		else :
			velocity.y -= gravity * delta
			move_air(delta)
	
	if is_zero_approx(smooth_y) :
		smooth_y = 0.0
	else :
		#print(smooth_y)
		smooth_y /= 1.125
		around.position.y = smooth_y + 0.688
	#Engine.time_scale = 0.2
		
var ppqp_water : PhysicsPointQueryParameters3D
func _coltest() -> void :
	for i in get_slide_collision_count() :
		var k := get_slide_collision(i)
		for j in k.get_collision_count() :
			var obj := k.get_collider(j)
			if obj is QmapbspQuakeClipProxyStatic :
				obj = obj.get_parent()
			if obj is QmapbspQuakeClipProxyAnimated :
				obj = obj.get_parent()
				
			if obj.has_method(&'_player_touch') :
				obj._player_touch(self, k.get_position(j), k.get_normal(j))
				return
	_watercoltest()
		
func _watercoltest() -> void :
	# water touch test
	if !ppqp_water :
		ppqp_water = PhysicsPointQueryParameters3D.new()
		ppqp_water.collision_mask = 0b10
		ppqp_water.collide_with_bodies = false
		ppqp_water.collide_with_areas = true
		
	fluid = null
	ppqp_water.position = origin.global_position
	var arr := get_world_3d().direct_space_state.intersect_point(ppqp_water)
	if !arr.is_empty() :
		fluid = arr[0]["collider"]
		
func _input(event : InputEvent) -> void :
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED :
		return
		
	if Input.is_action_just_pressed(&'q1_toggle_noclip') :
		toggle_noclip()
	
	if event is InputEventMouseMotion :
		var r : Vector2 = event.relative * -1
		head.rotate_x(r.y * sensitivity)
		around.rotate_y(r.x * sensitivity)
		
		var hrot = head.rotation
		hrot.x = clampf(hrot.x, -PI/2, PI/2)
		head.rotation = hrot
		
#func _fluid_enter(f : QmapbspQuakeFluidVolume) :
#	fluid = f
#
#func _fluid_exit(f : QmapbspQuakeFluidVolume) :
#	if f == fluid : fluid = null

#########################################

func toggle_noclip() :
	noclip = !noclip
