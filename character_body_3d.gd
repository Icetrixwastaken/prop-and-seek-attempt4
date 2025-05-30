extends CharacterBody3D

var speed
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const SNEAK_SPEED = 1.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003

#head bobbing variables
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
var t_bob = 0.0

# fov vars
const BASE_FOV = 75.0
const FOV_CHANGE = 5


#bullet go boom
var bullet = load("res://Scenes/bullet.tscn")
var instance
var pistol_removed = false


@onready var player = $"."
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var mesh_instance = $MeshInstance3D  # The player's visual mesh
@onready var raycast = $Head/Camera3D/RayCast3D  # Raycast to detect objects
@onready var collision_shape = $CollisionShape3D  # The player's collision
@onready var gun_barrel = $Head/Camera3D/Pistol/RayCast3D
@onready var pistol = $Head/Camera3D/Pistol #pistol pew pew

var health = 3

@export var texture_atlas : Texture  # Assign your texture atlas in the inspector



func _enter_tree():
	set_multiplayer_authority(str(name).to_int())


func _ready():
	if not is_multiplayer_authority(): return
	
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.current = true
	
#handle mesh switching
func _input(_event):
	if not is_multiplayer_authority(): return
	
	
	



func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _physics_process(delta: float) -> void:
		if not is_multiplayer_authority(): return
		
		# Add the gravity.
		if not is_on_floor():
			velocity += get_gravity() * delta
		
		#Handle Grid Snap
		if Input.is_action_just_pressed("clamp"):
			position.x = round(position.x)
			position.z = round(position.z)

		# Handle jump.
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
		
		#handle pew pew
		if Input.is_action_just_pressed("shoot"):
			if gun_barrel:
				play_shoot_effects.rpc()
				if raycast.is_colliding():
					var hit_player = raycast.get_collider()
					if hit_player is CharacterBody3D:
						hit_player.recieve_damage.rpc_id(hit_player.get_multiplayer_authority())
					
			
		
		
		#handle rotate
		if Input.is_action_just_pressed("rotate"):
			mesh_instance.rotate(Vector3(0, 1, 0), deg_to_rad(90))
			
		
		# Handle Sprinting
		if Input.is_action_pressed("sprint"):
			speed = SPRINT_SPEED
		elif Input.is_action_pressed("sneak"):
			speed = SNEAK_SPEED
		else: 
			speed = WALK_SPEED
			
		if Input.is_action_just_pressed("quit"):
			get_tree().quit()

		# Get the input direction and handle the movement/deceleration.
		# As good practice, you should replace UI actions with custom gameplay actions.
		var input_dir := Input.get_vector("left", "right", "up", "down")
		var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if is_on_floor():
			if direction:
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
			else:
				velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
				velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 2.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 2.0)
			
			
		#head bobbing
		t_bob += delta * velocity.length() * float(is_on_floor())
		camera.transform.origin = _headbob(t_bob)
		
		#FOV
		var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
		var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
		camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
		move_and_slide()
		try_change_mesh()
		if Input.is_action_just_pressed("hide_pistol"):
			remove_pistol.rpc()  # Only call on this peer
		
		
func _headbob(time) -> Vector3:
	
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	return pos
	
@rpc("any_peer","call_local")
func play_shoot_effects():
	if not pistol_removed:
		instance = bullet.instantiate()
		instance.position = gun_barrel.global_position
		instance.transform.basis = gun_barrel.global_transform.basis
		get_parent().add_child(instance)

@rpc("any_peer", "call_local")
func change_mesh_from_node(mesh_node_path: NodePath):
	var target_mesh = get_node(mesh_node_path)
	if target_mesh and target_mesh is MeshInstance3D:
		mesh_instance.mesh = target_mesh.mesh

		var material_count = target_mesh.get_surface_override_material_count()
		for i in range(material_count):
			var mat = target_mesh.get_surface_override_material(i)
			if mat == null:
				mat = StandardMaterial3D.new()
			if texture_atlas:
				mat.albedo_texture = texture_atlas
			mesh_instance.set_surface_override_material(i, mat)

		collision_shape.shape = mesh_instance.mesh.create_convex_shape()
		collision_shape.position.y = 1
		
func try_change_mesh():
	if Input.is_action_pressed("right_click") and raycast.is_colliding():
		var target = raycast.get_collider()

		# Try to find the mesh within the collider node
		var target_mesh = target.get_node_or_null("TargatableMesh")

		if target_mesh and target_mesh is MeshInstance3D:
			var path = target_mesh.get_path()
			change_mesh_from_node.rpc(path)

@rpc("call_local")  # Only runs on the calling peer
func remove_pistol():
	if pistol and pistol.is_inside_tree():
		pistol.queue_free()
		pistol_removed = true

@rpc("any_peer")		
func recieve_damage():
	health -= 1
	if health <= 0:
		#dead
		health = 3
		position = Vector3.ZERO
	
