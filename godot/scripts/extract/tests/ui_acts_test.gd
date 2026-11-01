extends SceneTree
const UiActs := preload("res://scripts/extract/ui_acts.gd")
const Cmp := preload("res://scripts/extract/tests/cmp.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var ext: String = a[1]
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ext.path_join("ui/index.json")))
	var t0 := Time.get_ticks_msec()
	var mine := UiActs.extract(a[0], idx, a[2])
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ext.path_join("ui/acts.json")))
	var mine2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a[2]))
	var d := Cmp.diff(ref, mine2, 1e-4)
	for x in d:
		print("D ", x)
	print("UIACTS acts=%d diffs=%d time=%.1fs" % [ref.size(), d.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
