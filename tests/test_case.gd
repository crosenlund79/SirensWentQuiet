extends RefCounted
## Base class for tests run by res://tests/run_tests.gd.

var tree: SceneTree
var test_id := ""
var failures := PackedStringArray()
var skipped := ""
var _nodes: Array[Node] = []


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append("%s: %s" % [test_id, msg])
	return cond


func check_eq(actual, expected, msg := "") -> bool:
	return check(actual == expected, "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])


func skip(reason: String) -> void:
	skipped = reason


## Adds a node under the root; it is freed after the test.
func add(node: Node) -> Node:
	tree.root.add_child(node)
	_nodes.append(node)
	return node


func frames(n := 1) -> void:
	for i in n:
		await tree.process_frame


func physics_frames(n := 1) -> void:
	for i in n:
		await tree.physics_frame


func seconds(s: float) -> void:
	await tree.create_timer(s, true, true).timeout


func cleanup() -> void:
	for a in ["move_up", "move_down", "move_left", "move_right", "fire"]:
		Input.action_release(a)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	if tree.current_scene != null and is_instance_valid(tree.current_scene):
		tree.current_scene.queue_free()
		tree.current_scene = null
	await frames(3)
