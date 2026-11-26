class_name StoryAudioGuard
extends RefCounted
## Experiment 012 (A): stops the story's audio when play returns to normal.
##
##   StoryAudioGuard.stop_all(get_tree())    # main menu, game load, scene changes
##
## Every node that plays story audio (the voice, the followers) is in the group
## GROUP (SPEC: "story_audio"). stop_all() first asks the story's own
## StoryAudio.stop_all() (when that class exists), then stops every audio
## player in the group (or under a group node) and frees group nodes that
## live directly under the SceneTree root (they would outlive a scene
## change). Nodes inside a scene are only stopped; the scene change frees
## them. Static, no Autoload; safe to call when nothing is playing.

const GROUP := "story_audio"

static var calls := 0          ## tests, F10
static var last_stopped := 0   ## players stopped by the last call
static var _busy := false


## Stops all story audio now. Returns the number of players stopped.
static func stop_all(tree: SceneTree = null) -> int:
	if _busy:                  # StoryAudio.stop_all() may call back here
		return 0
	_busy = true
	calls += 1
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	_call_story_stop()
	_busy = false
	var n := 0
	if tree == null:
		last_stopped = 0
		return 0
	for node in tree.get_nodes_in_group(GROUP):
		if not is_instance_valid(node):
			continue
		n += _stop_players(node)
		if node.get_parent() == tree.root and not node.is_queued_for_deletion():
			node.queue_free()
	last_stopped = n
	return n


## True when any story audio player is playing (the F10 Audio tab, tests).
static func playing_count(tree: SceneTree = null) -> int:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var n := 0
	for node in tree.get_nodes_in_group(GROUP):
		n += _count_playing(node)
	return n


static func _stop_players(node: Node) -> int:
	var n := 0
	if _is_player(node):
		if node.get("playing"):
			n += 1
		node.call("stop")
	for c in node.get_children():
		n += _stop_players(c)
	return n


static func _count_playing(node: Node) -> int:
	var n := 1 if _is_player(node) and node.get("playing") else 0
	for c in node.get_children():
		n += _count_playing(c)
	return n


static func _is_player(node: Node) -> bool:
	return node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D


## The story's own cleanup (src/story/story_audio.gd, agent S), looked up by
## name so this file doesn't depend on it.
static func _call_story_stop() -> void:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "StoryAudio":
			var script := load(str(c.get("path", ""))) as Script
			if script == null:
				return
			for m in script.get_script_method_list():
				if str(m.get("name", "")) == "stop_all" and (int(m.get("flags", 0)) & METHOD_FLAG_STATIC):
					script.call("stop_all")
					return
			return
