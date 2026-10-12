extends Node

## Tiny helper: forwards unhandled input to a Callable stored in meta.
## Used by overlays that need a key handler but do not want a full script file
## per screen. The handler is called with the InputEvent.

func _unhandled_input(event: InputEvent) -> void:
	var handler: Callable = get_meta("handler", Callable())
	if handler.is_valid():
		handler.call(event)
