extends Control
## Full-map minimap. Clicks stay on this control so the battle board does not also receive them.

var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	if owner != null:
		owner.call("paint_minimap", self)


func _gui_input(event: InputEvent) -> void:
	if owner == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			owner.call("minimap_begin", event.position, self)
		else:
			_dragging = false
			owner.call("minimap_end", event.position, self)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		owner.call("minimap_move", event.position, self)
		accept_event()
