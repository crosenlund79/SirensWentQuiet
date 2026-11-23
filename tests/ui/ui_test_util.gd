extends RefCounted
## Helpers for the UI tests (not a test file: no test_ prefix).


static func find_button(root: Node, text: String) -> BaseButton:
	if root == null:
		return null
	for c in root.get_children():
		if c is BaseButton and str(c.get("text")) == text:
			return c
		var r := find_button(c, text)
		if r != null:
			return r
	return null


static func find_named(root: Node, name: String) -> Node:
	return root.find_child(name, true, false) if root != null else null


static func all_label_text(root: Node) -> String:
	var out := PackedStringArray()
	_collect(root, out)
	return "\n".join(out)


static func _collect(n: Node, out: PackedStringArray) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	elif n is RichTextLabel:
		out.append((n as RichTextLabel).get_parsed_text())
	for c in n.get_children():
		_collect(c, out)


static func key(tree: SceneTree, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	tree.root.push_input(ev)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	tree.root.push_input(up)


static func click(tree: SceneTree) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	tree.root.push_input(ev)


## Records every emission of `sig` into `log` as [name, args...].
static func record(sig: Signal, name: String, log: Array) -> void:
	sig.connect(func(a = null):
		log.append(name if a == null else [name, a]))
