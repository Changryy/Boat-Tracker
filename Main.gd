extends Node2D

export(NodePath) onready var request_output = get_node(request_output) as Label
const DOUBLE_CLICK_TRESH = 300

var points = []
var anchor
var box = []

var zoom = 19

var loading = true
var is_zooming = false

var cam_pos = Vector2()

enum scroll_type {
	UNKNOWN,
	TOUCHPAD,
	MOUSE_WHEEL
}

var scroll_sensitivity = scroll_type.UNKNOWN

func _ready():
	RequestHandler.connect("forward_response", self, "_on_request_response")
	RequestHandler.connect("done", self, "_on_loading_finished")
	TileHandler.connect("send_image", self, "_on_tile_response")
	RequestHandler.request("points", Extract.tracker_url)
	RequestHandler.request("anchor", Extract.anchor_url)
	$Camera2D.zoom = TileHandler.zoom_to_scale(zoom)


func _on_request_response(id, result, response_code, headers, body, metadata):
	if id == "points":
		points = Extract.points(body)
		print("Loaded Points")
	if id == "anchor":
		anchor = Extract.anchor_pos(body)
		print("Loaded Anchor")
		box = Extract.box_pos(body)
		print("Loaded Box")
		$Camera2D.position = TileHandler.geo_to_pos(points[-1][0], points[-1][1])
		cam_pos = $Camera2D.position
		reload()
		draw_points(true)
	if id == "new_pos":
		var new_pos = Extract.last_pos(body)
		if Extract.geo(new_pos) == Extract.geo(points[-1]): return
		points.append(new_pos)
		draw_points()


func _on_tile_response(position, texture):
	var s = Sprite.new()
	s.position = Vector2(position.x, position.y) * TileHandler.SIZE + Vector2(1,1)*TileHandler.SIZE/2
	s.texture = texture
	get_node(str(position.z)).add_child(s)

func tile_sort(a, b):
	if typeof(a.metadata) != TYPE_VECTOR3: return false
	elif typeof(b.metadata) != TYPE_VECTOR3: return true
	var cam = TileHandler.pos_to_tile($Camera2D.position, zoom)
	var a_pos = Vector2(a.metadata.x, a.metadata.y)
	var b_pos = Vector2(b.metadata.x, b.metadata.y)
	return a_pos.distance_to(cam) < b_pos.distance_to(cam)

func get_tiles():
	var rect = $Camera2D.get_rekt(TileHandler.zoom_to_scale(zoom)) as Rect2
	
	var start = TileHandler.pos_to_tile(rect.position, zoom)
	start -= Vector2(1,1)*TileHandler.EXPAND
	
	var stop = TileHandler.pos_to_tile(rect.end, zoom)
	stop += Vector2(1,1)*TileHandler.EXPAND
	
	var tiles = []
	for x in range(start.x, stop.x+1):
		for y in range(start.y, stop.y+1):
			tiles.append(Vector3(x,y,zoom))
	return tiles

func draw_tiles():
	for tile in get_tiles():
		TileHandler.get_tile_texture(tile)
	RequestHandler.queue.sort_custom(self, "tile_sort")


func draw_points(move_cam=false):
	var new_points = []
	var sublist = []
	for point in points:
		sublist.append(TileHandler.geo_to_pos(point[0], point[1]))
		if len(sublist) >= 1000 or point == points[-1]:
			new_points.append(sublist.duplicate())
			sublist.clear()
	
	for line in get_tree().get_nodes_in_group("line"):
		line.queue_free()
	
	for x in new_points:
		var line = Line2D.new()
		line.points = x
		line.z_index = 1
		line.width = 5
		line.add_to_group("line")
		if move_cam: $Camera2D.position = x[-1]
		add_child(line)
	

var moving = false
var current_zoom = TileHandler.zoom_to_scale(zoom)
func _physics_process(delta):
	var scale_level = TileHandler.zoom_to_scale(zoom)
	
	# MOVEMENT
	var dir = Vector2()
	if Input.is_action_pressed("ui_right"): dir.x += 1
	if Input.is_action_pressed("ui_left"): dir.x -= 1
	if Input.is_action_pressed("ui_down"): dir.y += 1
	if Input.is_action_pressed("ui_up"): dir.y -= 1
	if (dir.length_squared() == 0 and moving) or \
		Input.is_action_just_released("left_mouse"): 
			draw_tiles()
	moving = dir.length_squared() != 0
	$Camera2D.translate(dir * scale_level * 10)
	
	request_output.text = str(len(RequestHandler.queue))
	
	current_zoom = lerp(current_zoom, scale_level, 0.2) as Vector2
	if current_zoom.distance_to(scale_level) < 8 and is_zooming:
		is_zooming = false
		current_zoom = scale_level
		$Camera2D.position = cam_pos
		reload()
	$Camera2D.zoom = current_zoom
	if is_zooming: $Camera2D.position = lerp($Camera2D.position, cam_pos, 0.2)
	
	# ZOOM WITH PGUP and PGDN
	if Input.is_action_just_pressed("ui_page_up"): change_zoom(1, true)
	elif Input.is_action_just_pressed("ui_page_down"): change_zoom(-1, true)

func change_zoom(dir, in_middle=false):
	if in_middle: cam_pos = $Camera2D.position
	if abs(dir) > 1:
		for i in range(min(dir, 0), max(dir, 0)): change_zoom(dir/abs(dir))
		return
	if dir > 0 and zoom == TileHandler.MAX_ZOOM: return
	elif dir < 0 and zoom == TileHandler.MIN_ZOOM: return
	is_zooming = true
	zoom += dir
	reload()

var last_zoom = 0
func zoom_on_position(pos, dir):
	if scroll_sensitivity == scroll_type.UNKNOWN: return
	if scroll_sensitivity == scroll_type.TOUCHPAD:
		if last_zoom > OS.get_ticks_msec() - 100: return
	last_zoom = OS.get_ticks_msec()
	change_zoom(dir)
	var new_pos = $Camera2D.position - pos
	new_pos /= $Camera2D.zoom.x
	new_pos *= TileHandler.zoom_to_scale(zoom).x
	new_pos += pos
	cam_pos = new_pos

var input_times = []

# Set scroll sensitivity based on if it detects a mouse or a touchpad
func update_scroll_sensetivity():
	if scroll_sensitivity != scroll_type.UNKNOWN: return
	var now = OS.get_ticks_msec()
	input_times.append(now)
	var amount = 0
	for value in input_times:
		if value > now - 100: amount += 1
	if amount > 1: scroll_sensitivity = scroll_type.TOUCHPAD
	elif now > input_times[0] + 100: scroll_sensitivity = scroll_type.MOUSE_WHEEL
	else: return
	input_times.clear()

func _input(event):
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == BUTTON_WHEEL_UP:
				zoom_on_position(get_global_mouse_position(), 1)
				update_scroll_sensetivity()
			if event.button_index == BUTTON_WHEEL_DOWN:
				zoom_on_position(get_global_mouse_position(), -1)
				update_scroll_sensetivity()
		if event.button_index == BUTTON_LEFT and event.doubleclick:
			cam_pos = get_global_mouse_position()
			change_zoom(2)
	if (event is InputEventMouseMotion and Input.is_action_pressed("left_mouse"))\
	or (event is InputEventScreenDrag):
		$Camera2D.position -= event.relative * TileHandler.zoom_to_scale(zoom)


func sort_zoom():
	for node in get_tree().get_nodes_in_group("zoom level"):
		if node.name == str(zoom): node.visible = true
		else: node.visible = false

func reload():
	loading = true
	RequestHandler.stop()
	if !has_node(str(zoom)):
		var new_zoom = Node2D.new()
		new_zoom.name = str(zoom)
		new_zoom.position = -TileHandler.ROOT
		new_zoom.scale = TileHandler.zoom_to_scale(zoom)
		new_zoom.add_to_group("zoom level")
		add_child(new_zoom)
	draw_tiles()
	move_child(get_node(str(zoom)), get_child_count())

func _on_loading_finished(): loading = false


func _on_in_pressed(): change_zoom(1, true)
func _on_out_pressed(): change_zoom(-1, true)

func _on_Refresher_timeout(): RequestHandler.request("new_pos", Extract.anchor_url, null, true)
