extends Node
signal send_image(position, texture)

const SIZE = 256
const EXPAND = 2

const ROOT = Vector2(1,1) * 67108864
const MAX_ZOOM = 19
const MIN_ZOOM = 4


func ln(x): return float(log(x) / log(exp(1)))
func asinh(x): return float(ln(x + sqrt(pow(x, 2) + 1)))



func _get_image(body):
	var image = Image.new()
	var error = image.load_png_from_buffer(body)
	if error != OK:
		push_error("Couldn't load the image.")
	image.lock()
	var texture = ImageTexture.new()
	texture.create_from_image(image)
	return texture

func _ready():
	RequestHandler.connect("forward_response", self, "_on_request_response")

func _on_request_response(id, result, response_code, headers, body, metadata):
	if id == "maptile":
		emit_signal("send_image", metadata, _get_image(body))


func get_tilename(tile):
	return "https://tile.openstreetmap.org/%s/%s/%s.png" % [tile.z, tile.x, tile.y]


func get_tile_texture(tile):
	RequestHandler.request("maptile", get_tilename(tile), tile)


func geo_to_tile(lat_deg, lon_deg, zoom, as_int=true):
	var lat_rad = deg2rad(lat_deg)
	var n = pow(2.0,zoom)
	var xtile = (lon_deg + 180.0) / 360.0 * n
	var ytile = (1.0 - asinh(tan(lat_rad)) / PI) / 2.0 * n
	if as_int:
		xtile = int(xtile)
		ytile = int(ytile)
	return Vector3(xtile, ytile, zoom)


func geo_to_pos(lat, lon, zoom=19):
	var pos = geo_to_tile(lat, lon, zoom, false)
	return Vector2(pos.x, pos.y) * SIZE - ROOT

func pos_to_tile(pos, zoom, as_int=true):
	pos += ROOT
	pos /= zoom_to_scale(zoom)
	pos /= SIZE
	if as_int: pos = pos.floor()
	return pos

func zoom_to_scale(zoom):
	return Vector2(1,1) * pow(2, MAX_ZOOM-zoom)

