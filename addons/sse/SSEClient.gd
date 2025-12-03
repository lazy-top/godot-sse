class_name SSEClient
extends Node
# 信号定义
signal message_received(data: String)
signal error_occurred(error_message: String)
signal connection_opened()
signal event_received(event_name, data, id)


# 自动重连间隔（毫秒）
var reconnect_delay: int = 3000
# 私有变量
var _http_client: HTTPClient
var _url: String
var _parsed:Dictionary={}
var _is_connected: bool = false
var _should_reconnect: bool = false
var _connection_in_progress: bool = false
#流式处理配置
var _buffer: PackedByteArray
var _event_buffer: String
var _current_event: Dictionary

# SSE事件字段
var _event_name: String
var _data: String
var _id: String
var _retry: int


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_http_client = HTTPClient.new()
	_should_reconnect = true
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if _connection_in_progress:
		_poll_connection()
# 连接到SSE服务器
func connect_to_url(url: String) -> void:
	_url = url
	_parsed=parse_url(_url)
	_start_connection()
# 关闭连接
func close() -> void:
	_should_reconnect = false
	_is_connected = false
	_connection_in_progress = false
	print("SSE closed.")
# 开始连接
func _start_connection() -> void:
	if _connection_in_progress:
		return
	
	_connection_in_progress = true
	print("Connecting to SSE: ", _url)
	
	var error = _http_client.connect_to_host(_parsed.host, int(_parsed.port))
	if error != OK:
		_handle_error("Failed to connect to host: " + str(error))
		return
		
# 轮询连接状态和处理数据
func _poll_connection() -> void:
	_http_client.poll()
	
	var status = _http_client.get_status()
	
	match status:
		HTTPClient.STATUS_DISCONNECTED:
			# 连接断开，尝试重连
			if _should_reconnect:
				_attempt_reconnect()
		
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			# 连接中，继续等待
			pass
		
		HTTPClient.STATUS_CONNECTED:
			# 连接建立，发送请求
			if not _is_connected:
				_establish_connection()
		
		HTTPClient.STATUS_REQUESTING, HTTPClient.STATUS_BODY:
			# 接收数据
			_process_response()
		
		_:
			# 其他状态处理
			if status == HTTPClient.STATUS_CANT_CONNECT or status == HTTPClient.STATUS_CANT_RESOLVE:
				_handle_error("Connection failed with status: " + str(status))
# 建立连接并发送请求
func _establish_connection() -> void:
	var headers = PackedStringArray([
		"Accept: text/event-stream",
		"Cache-Control: no-cache"
	])
	
	var error = _http_client.request(HTTPClient.METHOD_GET, _parsed.path_query, headers)
	if error != OK:
		_handle_error("Request failed: " + str(error))
		return
	
	_is_connected = true
	connection_opened.emit()
	print("SSE connection opened.")

# 接收和处理数据
func _receive_data() -> void:
	while _http_client.get_status() == HTTPClient.STATUS_BODY:
		var chunk_size = _http_client.get_response_body_length()
		if chunk_size > 0:
			var chunk = _http_client.read_response_body_chunk()
			if chunk.size() > 0:
				_process_chunk(chunk)

# 处理数据块
func _process_chunk(chunk: PackedByteArray) -> void:
	var text = chunk.get_string_from_utf8()
	if text.is_empty():
		return
	
	# 按行分割处理
	var lines = text.split("\n")
	for line in lines:
		line = line.strip_edges()
		if line.is_empty():
			continue
		
		# 处理SSE数据格式
		if line.begins_with("data:"):
			var data = line.substr(5).strip_edges()
			message_received.emit(data)
		elif line.begins_with("event:"):
			# 可以处理不同类型的事件
			pass
		elif line.begins_with("id:"):
			# 处理事件ID
			pass
		elif line.begins_with("retry:"):
			# 处理重试时间
			var retry_time = line.substr(6).strip_edges()
			if retry_time.is_valid_int():
				reconnect_delay = retry_time.to_int()
func _process_response():
	if _http_client.get_status() != HTTPClient.STATUS_BODY:
		return
	
	# 检查是否有响应数据可用
	if _http_client.has_response():
		# 读取响应体块
		var chunk = _http_client.read_response_body_chunk()
		if chunk.size() > 0:
			_buffer.append_array(chunk)
			_parse_buffer()
	
	# 检查连接是否仍然有效
	if _http_client.get_status() == HTTPClient.STATUS_DISCONNECTED:
		_handle_error("Connection failed" )

	pass
func _parse_buffer() -> void:
	
	if _buffer.size() == 0:
		return
	
	# 将字节数组转换为字符串
	var text = _buffer.get_string_from_utf8()
	if text == null:
		# UTF-8解码失败，清空缓冲区
		_buffer = PackedByteArray()
		return
	
	# 查找最后一个完整的事件（以两个换行符结束）
	var last_double_newline = text.rfind("\n\n")
	if last_double_newline == -1:
		last_double_newline = text.rfind("\r\n\r\n")
	
	if last_double_newline != -1:
		# 提取完整的事件数据（包括最后一个双换行符）
		var complete_events = text.substr(0, last_double_newline + 2)
		_event_buffer += complete_events
		
		# 处理所有完整的事件
		var events = _event_buffer.split("\n\n")
		for i in range(events.size() - 1):  # 最后一个可能不完整
			var event_text = events[i]
			_process_single_event(event_text)
		
		# 保留不完整的部分
		_event_buffer = events[events.size() - 1] if events.size() > 0 else ""
		
		# 更新缓冲区，只保留未处理的数据
		var processed_bytes = text.substr(0, last_double_newline + 2).to_utf8_buffer().size()
		if processed_bytes <= _buffer.size():
			_buffer = _buffer.slice(processed_bytes)
		else:
			_buffer = PackedByteArray()
	else:
		# 没有完整的事件，累积到缓冲区
		_event_buffer += text
		_buffer = PackedByteArray()
func _process_single_event(event_text: String) -> void:
	if event_text.strip_edges().is_empty():
		return
	
	var lines = event_text.split("\n")
	var event_data = {
		"event": "message",
		"data": "",
		"id": "",
		"retry": null
	}
	
	for line in lines:
		if line.strip_edges().is_empty():
			continue
		
		var colon_index = line.find(":")
		if colon_index == -1:
			# 无效行，跳过
			continue
		
		var field_name = line.substr(0, colon_index).strip_edges()
		var field_value = line.substr(colon_index + 1).strip_edges()
		
		match field_name:
			"event":
				event_data.event = field_value
			"data":
				if event_data.data.is_empty():
					event_data.data = field_value
				else:
					event_data.data += "\n" + field_value
			"id":
				event_data.id = field_value
			"retry":
				if field_value.is_valid_int():
					event_data.retry = field_value.to_int()
	
	# 只有在有数据时才触发事件
	if not event_data.data.is_empty():
		event_received.emit(event_data.event, event_data.data, event_data.id)
		


# 错误处理
func _handle_error(error_message: String) -> void:
	_is_connected = false
	_connection_in_progress = false
	error_occurred.emit(error_message)
	printerr("SSE error: ", error_message)
	
	if _should_reconnect:
		_attempt_reconnect()
		
# 尝试重连
func _attempt_reconnect() -> void:
	if not _should_reconnect:
		return
	
	_connection_in_progress = false
	_is_connected = false
	
	# 延迟重连
	print("Reconnecting in ", reconnect_delay, "ms...")
	await get_tree().create_timer(reconnect_delay / 1000.0).timeout
	
	if _should_reconnect:
		_start_connection()
func parse_url(url: String) -> Dictionary:
	var result = {
		"protocol": "",
		"host": "",
		"port": "",
		"path_query": ""
	}
	
	# 提取协议
	var protocol_end = url.find("://")
	if protocol_end != -1:
		result.protocol = url.substr(0, protocol_end)
		url = url.substr(protocol_end + 3)  # 移除协议部分
	
	# 提取主机和端口
	var host_end = url.find("/")
	if host_end == -1:
		host_end = url.length()
	
	var host_port = url.substr(0, host_end)
	var colon_pos = host_port.find(":")
	
	if colon_pos != -1:
		result.host = host_port.substr(0, colon_pos)
		result.port = host_port.substr(colon_pos + 1)
	else:
		result.host = host_port
		# 设置默认端口
		if result.protocol == "https":
			result.port = "443"
		else:
			result.port = "80"
	
	# 提取路径和查询参数
	if host_end < url.length():
		var path_query = url.substr(host_end)
		result.path_query = path_query
	return result
