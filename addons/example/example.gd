extends Node2D

var sse_client: SSEClient

func _ready():
	# 创建SSEClient实例
	sse_client = SSEClient.new()
	add_child(sse_client)
	
	# 连接信号
	sse_client.connection_opened.connect(_on_connection_opened)
	sse_client.message_received.connect(_on_message_received)
	sse_client.event_received.connect(_on_event_received)
	sse_client.error_occurred.connect(_on_error_occurred)
	
	# 连接到SSE服务器
	sse_client.connect_to_url("http://localhost:3000/events")

func _on_connection_opened():
	print("SSE连接已建立")

func _on_message_received(data: String):
	print("收到消息:", data)
	
	# 如果是JSON数据，可以解析
	var json = JSON.new()
	var error = json.parse(data)
	if error == OK:
		var parsed_data = json.get_data()
		print("解析后的数据:", parsed_data)

func _on_event_received(event_name: String, data: String, id: String):
	print("事件:", event_name, " 数据:", data, " ID:", id)
	
	# 根据不同事件类型处理
	#match event_name:
		#"message":
			#handle_chat_message(data)
		#"update":
			#handle_data_update(data)
		#"notification":
			#show_notification(data)

func _on_error_occurred(error_message: String):
	print("发生错误:", error_message)
