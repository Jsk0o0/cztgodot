extends Node
## 启动声明: 黑底文字, 约 5 秒后 (或按任意键) 进入标题画面

const NEXT := "res://scenes/title.tscn"
var _leaving := false
var _box: Control


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 18)
	center.add_child(_box)
	_box.add_child(_label("同 人 作 品 声 明", Game.font_menu, 30, Color(0.86, 0.74, 0.50)))
	var body := _label(Game.DISCLAIMER, Game.font_body, 17, Color(0.92, 0.9, 0.84))
	body.add_theme_constant_override("line_spacing", 8)
	_box.add_child(body)
	_box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_box, "modulate:a", 1.0, 1.0)
	tw.tween_interval(4.0)
	tw.tween_callback(_leave)


func _label(t: String, f: Font, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


func _input(e: InputEvent) -> void:
	if e.is_pressed() and (e is InputEventKey or e is InputEventMouseButton or e is InputEventJoypadButton):
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	var tw := create_tween()
	tw.tween_property(_box, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): get_tree().change_scene_to_file(NEXT))
