extends Camera2D


func get_rekt(z):
	var size = get_viewport().size * z
	var rect = Rect2(position - size/2, size)
	return rect

