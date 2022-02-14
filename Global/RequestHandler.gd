extends Node
signal forward_response(id, result, response_code, headers, body, metadata)
signal done()

var http_request

var queue = []
var current
var working = false

var finished = []


func request(id, url, metadata=null, force=false):
	var working_on = []
	for x in queue:
		working_on.append(x.url)
	if (not force) and ((url in finished) or (url in working_on)): return
	queue.append({id=id,url=url,metadata=metadata})
	if not working: _fetch_next()

func _ready():
	http_request = HTTPRequest.new()
	http_request.connect("request_completed", self, "_on_receive_response")
	http_request.use_threads = false
	add_child(http_request)



func _on_receive_response(result, response_code, headers, body):
	if result == 0 and response_code == 200:
		if not (current.url in finished):
			finished.append(current.url)
		emit_signal("forward_response", current.id, result,
				response_code, headers, body, current.metadata)
	if len(queue) > 0: return _fetch_next()
	working = false
	emit_signal("done")

func _fetch_next():
	working = true
	current = queue.pop_front()
	http_request.request(current.url)

func stop():
	queue.clear()






