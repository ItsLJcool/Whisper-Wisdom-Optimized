@tool

extends Node2D

class_name BaseObject

enum ColorType {
	Yellow = 0,
	Cyan = 1,
	Red = 2,
	Pink = 3, #Pinkj... lol
}

@export var move_speed:int = 15

@export var COLOR_TYPE:ColorType = ColorType.Yellow:
	set(value):
		COLOR_TYPE = value
		on_color_type_change(value)
	
func color_type_to_string(type:ColorType = COLOR_TYPE):
	return ColorType.keys()[type].capitalize()

func on_color_type_change(value):
	pass

enum ObjectType {
	IMMOVABLE,
	MOVABLE,
	PASSABLE,
}

func object_type_to_string(type:ObjectType = current_object_type):
	return ObjectType.keys()[type].capitalize()

@export var OBJECT_TYPE:ObjectType = ObjectType.MOVABLE:
	set(value):
		OBJECT_TYPE = value;
		current_object_type = value;
var current_object_type:ObjectType = OBJECT_TYPE;

# Gets all scenes or "nodes" of the class type.
func get_all(node):
	var data:Array = [];
	if node is BaseObject:
		data.push_back(node)
	for child in node.get_children():
		for n in get_all(child):
			data.push_back(n)
	return data;

@export var TileLayer:TileMapLayer

var tile_size:Vector2i:
	get:
		if !TileLayer:
			return Vector2i(128, 128)
		return TileLayer.tile_set.tile_size

var target_position:Vector2 = Vector2.ZERO:
	set(value):
		target_position = value;
		if TileLayer:
			GRID_POSITION = TileLayer.local_to_map(TileLayer.to_local(target_position))
	get:
		if TileLayer:
			GRID_POSITION = TileLayer.local_to_map(TileLayer.to_local(target_position))
		return target_position
		
var prev_target_position:Vector2 = Vector2.ZERO
@export var _last_direction:Vector2 = Vector2.ZERO

var GRID_POSITION:Vector2:
	get:
		if TileLayer:
			GRID_POSITION = TileLayer.local_to_map(TileLayer.to_local(target_position))
			return GRID_POSITION;
		else:
			return GRID_POSITION;

func _ready() -> void:
	Global.connect("on_object_move", on_object_move)
	Global.connect("force_to_target", force_to_target)
	target_position = position
	prev_target_position = target_position

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		var new_x = round(position.x / tile_size.x) * tile_size.x
		var new_y = round(position.y / tile_size.y) * tile_size.y
		target_position = Vector2(new_x, new_y)
		prev_target_position = target_position
		position = target_position
		return
	
	position = lerp(position, target_position, delta*move_speed)

func move_towards_target(current_position: Vector2, target_position: Vector2, speed: float) -> Vector2:
	var direction = (target_position - current_position).normalized()
	var new_position = current_position + direction * speed
	if current_position.distance_to(target_position) < speed:
		new_position = target_position
	return new_position

enum MoveProperties {
	ALLOW_SLIDING,
	CHECK_TILE,
	IS_SLIDING,
	EMIT_MOVE,
}
func moveType_to_string(type:MoveProperties = MoveProperties.ALLOW_SLIDING):
	return MoveProperties.keys()[type].capitalize()

var _properties_default:Array = [
	MoveProperties.ALLOW_SLIDING,
	MoveProperties.CHECK_TILE,
	MoveProperties.EMIT_MOVE
];

# indexes of all moves made, will cap it at some point
var buffer_moves:Array = []

func do_step_move(idx:int):
	pass

func move(direction:Vector2, properties:Array = _properties_default):
	_last_direction = direction.normalized()
		
	prev_target_position = target_position
	target_position.x += direction.x * tile_size.x
	target_position.y += direction.y * tile_size.y
	
	if properties.has(MoveProperties.CHECK_TILE):
		tile_handle(_last_direction, properties)
	
	if properties.has(MoveProperties.EMIT_MOVE):
		Global.on_object_move.emit(_last_direction, properties, self)

func tile_handle(direction:Vector2, properties:Array):
	if not TileLayer:
		return
	
	var customData = TileLayer.get_cell_tile_data(GRID_POSITION)
	var next_customData = TileLayer.get_cell_tile_data(GRID_POSITION + direction)
	
	if customData:
		var allowed_walk = get_allow_walk(customData)
		if not allowed_walk:
			current_object_type = ObjectType.IMMOVABLE
			move(-direction, [MoveProperties.CHECK_TILE])
		
		if customData.get_custom_data("ice") and properties.has(MoveProperties.ALLOW_SLIDING) and not properties.has(MoveProperties.IS_SLIDING):
			var calc = ice_calc(direction)
			if calc == Vector2.ZERO:
				return
			var _properties =  [MoveProperties.IS_SLIDING, MoveProperties.CHECK_TILE];
			
			move(calc, _properties)

func ice_calc(direction:Vector2) -> Vector2:
		
	for object in get_all(get_tree().root):
		if object == self:
			continue
		if object.GRID_POSITION == GRID_POSITION:
			object.move(direction)
			return direction;
	var _grid_position = GRID_POSITION + direction
	var ice_data = TileLayer.get_cell_tile_data(_grid_position)
	var final_calc:Vector2 = direction
	while((ice_data and ice_data.get_custom_data("ice"))):
		var _break:bool = false
		
		for object in get_all(get_tree().root):
			if object == self:
				continue
			if object.GRID_POSITION == _grid_position:
				_break = true
				final_calc -= direction
				object.move(direction)
				break
		
		if _break:
			break;
		
		final_calc += direction
		_grid_position = GRID_POSITION + final_calc
		ice_data = TileLayer.get_cell_tile_data(_grid_position)
	_grid_position = GRID_POSITION + final_calc
	ice_data = TileLayer.get_cell_tile_data(_grid_position)
	if ice_data:
		if not get_allow_walk(ice_data):
			final_calc -= direction
	
	return final_calc

func get_allow_walk(data):
		return not data.get_custom_data("wall")

func force_to_target():
	position = target_position

func on_object_move(directon:Vector2, properties:Array, object:BaseObject):
	if object == self:
		return
	
	# Ice Physics fix
	var customData = TileLayer.get_cell_tile_data(GRID_POSITION - directon)
	if customData:
		properties = properties.filter(func(item): return item != MoveProperties.ALLOW_SLIDING)
	
	if current_object_type == ObjectType.IMMOVABLE:
		if object.GRID_POSITION == GRID_POSITION:
			object.move(-directon, properties)
	elif current_object_type == ObjectType.MOVABLE:
		if object.GRID_POSITION == GRID_POSITION:
			move(directon, properties)
	
	current_object_type = OBJECT_TYPE
