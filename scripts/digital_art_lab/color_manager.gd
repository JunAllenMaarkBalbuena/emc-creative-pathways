class_name ColorManager
extends RefCounted

## Manages primary/secondary colours, history, and favourites.
## Serialised as part of player preferences.

signal color_changed(color: Color)
signal swapped

var primary := Color.BLACK
var secondary := Color.WHITE
var recent: Array[Color] = []
var favorites: Array[Color] = []
var max_recent := 10


func set_primary(c: Color):
	primary = c
	_add_recent(c)
	color_changed.emit(c)


func set_secondary(c: Color):
	secondary = c


func swap():
	var tmp := primary
	primary = secondary
	secondary = tmp
	swapped.emit()
	color_changed.emit(primary)


func _add_recent(c: Color):
	# Avoid duplicates at the front
	recent.erase(c)
	recent.push_front(c)
	while recent.size() > max_recent:
		recent.pop_back()


func toggle_favorite(c: Color):
	if favorites.has(c):
		favorites.erase(c)
	else:
		favorites.append(c)


func is_favorite(c: Color) -> bool:
	return favorites.has(c)
