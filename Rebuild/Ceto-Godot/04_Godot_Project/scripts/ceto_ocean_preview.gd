extends Node3D

## CPU-rendered preview for the converted Ceto numerical backend.
## This is a lightweight Godot presentation layer, not the original Unity ocean renderer.

const Simulation = preload("res://scripts/ceto_ocean_simulation.gd")

@export_range(16, 256, 16) var fft_size := 64
@export_range(0.05, 1.0, 0.05) var update_interval := 0.2

var _simulation
var _surface: MeshInstance3D
var _elapsed := 0.0
var _update_clock := 0.0
var _water_material: StandardMaterial3D


func _ready() -> void:
	_simulation = Simulation.new()
	_simulation.configure(fft_size, 4, "unified", 8.0, 25.0, 0.64, 1.0)
	_simulation.initialize()
	_simulation.update(0.0)

	_create_environment()
	_create_camera()
	_create_light()
	_create_surface()
	_rebuild_surface()


func _process(delta: float) -> void:
	_elapsed += delta
	_update_clock += delta
	if _update_clock < update_interval:
		return
	_update_clock = 0.0
	_simulation.update(_elapsed)
	_rebuild_surface()


func _create_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.035, 0.065)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.64, 0.75)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)


func _create_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 190.0, 260.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	add_child(camera)


func _create_light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	light.light_energy = 1.15
	add_child(light)


func _create_surface() -> void:
	_surface = MeshInstance3D.new()
	_water_material = StandardMaterial3D.new()
	_water_material.albedo_color = Color(0.012, 0.16, 0.22)
	_water_material.metallic = 0.08
	_water_material.roughness = 0.16
	_water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_surface.material_override = _water_material
	add_child(_surface)


func _surface_vertex(x: int, y: int) -> Vector3:
	var size: int = int(_simulation.size)
	var u := float(x) / float(size - 1)
	var v := float(y) / float(size - 1)
	var world_size: float = float(_simulation.grid_sizes.x)
	var world_x: float = (u - 0.5) * world_size
	var world_z: float = (v - 0.5) * world_size
	var displacement: Vector3 = _simulation.sample_surface(world_x, world_z)
	return Vector3(
		world_x + displacement.x,
		displacement.y,
		world_z + displacement.z
	)


func _rebuild_surface() -> void:
	var size: int = int(_simulation.size)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for y in range(size - 1):
		for x in range(size - 1):
			var u0 := float(x) / float(size - 1)
			var u1 := float(x + 1) / float(size - 1)
			var v0 := float(y) / float(size - 1)
			var v1 := float(y + 1) / float(size - 1)

			var p00 := _surface_vertex(x, y)
			var p10 := _surface_vertex(x + 1, y)
			var p01 := _surface_vertex(x, y + 1)
			var p11 := _surface_vertex(x + 1, y + 1)

			tool.set_uv(Vector2(u0, v0))
			tool.add_vertex(p00)
			tool.set_uv(Vector2(u0, v1))
			tool.add_vertex(p01)
			tool.set_uv(Vector2(u1, v0))
			tool.add_vertex(p10)

			tool.set_uv(Vector2(u1, v0))
			tool.add_vertex(p10)
			tool.set_uv(Vector2(u0, v1))
			tool.add_vertex(p01)
			tool.set_uv(Vector2(u1, v1))
			tool.add_vertex(p11)

	tool.generate_normals()
	_surface.mesh = tool.commit()
