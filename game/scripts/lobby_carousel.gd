extends Control

const UiPalette = preload("res://scripts/ui_palette.gd")
const ROUNDED_MASK := preload("res://assets/lobby_art/rounded_mask.gdshader")
const SLIDES := [
	["res://assets/lobby_art/sakura.webp", "海边樱花"],
	["res://assets/lobby_art/library.webp", "午后图书馆"],
	["res://assets/lobby_art/lanterns.webp", "灯笼夜祭"],
]
const HOLD_SECONDS := 7.0
const FADE_SECONDS := 0.55

var reduced_motion := false
var active_slide := -1
var _slides: Array = []
var _dots: Array[Panel] = []
var _current: TextureRect
var _incoming: TextureRect
var _timer: Timer
var _fade: Tween
var _pending_slide := -1
var _mask: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask = ShaderMaterial.new()
	_mask.shader = ROUNDED_MASK
	_current = _make_layer("CurrentArt")
	_incoming = _make_layer("IncomingArt")
	_incoming.hide()
	resized.connect(_resize_mask)
	_resize_mask()

	for slide in SLIDES:
		if ResourceLoader.exists(slide[0], "Texture2D"):
			_slides.append(slide)
	if _slides.is_empty():
		return
	if _slides.size() > 1:
		_build_dots()
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.wait_time = HOLD_SECONDS
		_timer.timeout.connect(func() -> void: show_slide((active_slide + 1) % _slides.size()))
		add_child(_timer)
	show_slide(0)


func _make_layer(node_name: String) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = node_name
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.material = _mask
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return layer


func _resize_mask() -> void:
	_mask.set_shader_parameter("frame_size", size)


func _build_dots() -> void:
	var controls := PanelContainer.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(UiPalette.NIGHT_PANEL, 0.48)
	backdrop.set_corner_radius_all(32)
	backdrop.content_margin_left = 8
	backdrop.content_margin_right = 8
	controls.add_theme_stylebox_override("panel", backdrop)
	add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	var half_width := (44.0 * _slides.size() + 16.0) / 2.0
	controls.offset_left = -half_width
	controls.offset_right = half_width
	controls.offset_top = -68
	controls.offset_bottom = -22

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	controls.add_child(row)
	var empty := StyleBoxEmpty.new()
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = UiPalette.MILK
	dot_style.set_corner_radius_all(6)
	for index in _slides.size():
		var button := Button.new()
		button.name = "SlideDot%d" % (index + 1)
		button.tooltip_text = _slides[index][1]
		button.custom_minimum_size = Vector2(44, 46)
		button.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, empty)
		button.pressed.connect(show_slide.bind(index))
		row.add_child(button)
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.custom_minimum_size = Vector2(12, 12)
		dot.add_theme_stylebox_override("panel", dot_style)
		center.add_child(dot)
		_dots.append(dot)


func show_slide(index: int) -> void:
	if index < 0 or index >= _slides.size() or not is_inside_tree():
		return
	if _fade != null:
		_pending_slide = index
		return
	if index == active_slide:
		_restart_timer()
		return
	var artwork := ResourceLoader.load(_slides[index][0], "Texture2D") as Texture2D
	if artwork == null:
		_restart_timer()
		return
	if _timer != null:
		_timer.stop()
	if reduced_motion or _current.texture == null:
		_current.texture = artwork
		_activate(index)
		_restart_timer()
		return

	_incoming.texture = artwork
	_incoming.modulate.a = 0.0
	_incoming.show()
	_fade = create_tween()
	_fade.tween_property(_incoming, "modulate:a", 1.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE)
	_fade.finished.connect(_finish_fade.bind(index))


func _finish_fade(index: int) -> void:
	_current.texture = _incoming.texture
	_incoming.texture = null
	_incoming.hide()
	_fade = null
	_activate(index)
	var requested := _pending_slide
	_pending_slide = -1
	if requested >= 0 and requested != active_slide:
		show_slide(requested)
	else:
		_restart_timer()


func _activate(index: int) -> void:
	active_slide = index
	for dot in _dots.size():
		_dots[dot].modulate.a = 1.0 if dot == index else 0.56


func _restart_timer() -> void:
	if _timer != null and not reduced_motion:
		_timer.start()
