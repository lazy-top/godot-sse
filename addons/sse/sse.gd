@tool
extends EditorPlugin

const SSEClientNode = preload("SSEClient.gd")

func _enable_plugin() -> void:
	# 注册自定义节点
	add_custom_type("SSEClient", "Node", SSEClientNode, null)
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	# 清理插件
	remove_custom_type("SSEClient")
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	pass


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	pass
