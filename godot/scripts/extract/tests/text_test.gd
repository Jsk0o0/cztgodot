extends SceneTree
## 测试: Big5 解码 + 繁转简和 Python 一致 (样本由 Python 生成: [[hex, big5 解码, t2s], ...])
const Txt := preload("res://scripts/extract/text.gd")


func _init() -> void:
	var a: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var t0 := Time.get_ticks_msec()
	var bad_b := 0
	var bad_t := 0
	for e in a:
		var s := Txt.big5(PackedByteArray(str(e[0]).hex_decode()))
		if s != e[1]:
			bad_b += 1
			if bad_b <= 3:
				print("B5 ", e[1], " | ", s)
		var t := Txt.t2s(e[1])
		if t != e[2]:
			bad_t += 1
			if bad_t <= 5:
				print("T2S ", e[2], " | ", t)
	print("TEXT n=%d big5_bad=%d t2s_bad=%d time=%.1fs" % [a.size(), bad_b, bad_t, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
