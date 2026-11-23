class_name IntroOverlay
extends CanvasLayer
## A few lines over black at the start of a new run (SPEC §7.8). Owner: U. Foundation stub.

signal done


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS


func play() -> void:
	done.emit.call_deferred()
