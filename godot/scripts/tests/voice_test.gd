extends SceneTree
## 测试: 对白配音 (同人新增) —— Dialog.show_text 有这句的语音文件就播, 关窗停; 另一个窗口关掉不打断正在播的这句;
## 设定关掉不播; 没有语音文件的句子不播; mod 里的 voice/<key>.ogg (Mods.voices) 优先。
## 要先用 tools/gen_voice.py 生成 talks1-1 事件 10 的配音到 extracted_voice/sichuan
## godot --path godot -s res://scripts/tests/voice_test.gd -- --bg   → VOICE PASS / FAIL


var _fail := 0


func _ok(c: bool, what: String) -> void:
	print("  %s %s" % ["ok" if c else "FAIL", what])
	if not c:
		_fail += 1


func _initialize() -> void:
	await process_frame
	var Game = root.get_node("/root/Game")
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.extracted_dir.path_join("game/events/talks1-1.json")))
	var lines: Array = []
	for ins in d.codes[d.events["10"]]:
		if ins[1] == "text" and str(ins[12]).contains("车芸："):
			lines.append(str(ins[12]))
	var old: Variant = Game.settings.get_value("audio", "voice_on", true)
	Game.settings.set_value("audio", "voice_on", true)   # 只改内存, 不存盘
	var Mods = root.get_node("/root/Mods")
	if OS.get_cmdline_user_args().has("--expect-mod-voices"):   # --mod=四川话配音.pod 时: 包里的配音进了 Mods.voices
		_ok(Mods.voices.has(Game.voice_key(lines[0])), "pod 里的配音已加载 (%d 句)" % Mods.voices.size())
	var dlg = load("res://scripts/field/dialog.gd").new()
	root.add_child(dlg)
	var box := [0, 150, 150, 470, 150, 470, 0, 510, 120, 19]
	dlg.show_text(1, box, lines[0], Color.BLACK, "")
	var w: Variant = dlg.windows[1]
	_ok(w.voiced == Game.voice_key(lines[0]), "第一句有配音 key=%s" % w.voiced)
	await process_frame
	_ok(Game._voice != null and Game._voice.playing, "在播")
	dlg.show_text(1, box, lines[1], Color.BLACK, "")   # 同一角色换下一句: 关旧窗 → 停旧的, 播新的
	_ok(Game._voice_key == Game.voice_key(lines[1]) and Game._voice.playing, "下一句接着播")
	dlg.show_text(2, box, lines[2], Color.BLACK, "")   # 另一个窗口开始播
	dlg.close(1)                                        # 关掉前一个窗口: 不能把第 3 句停掉
	await process_frame
	_ok(Game._voice_key == Game.voice_key(lines[2]) and Game._voice.playing, "关别的窗口不打断当前这句")
	dlg.close(2)
	await process_frame
	_ok(not Game._voice.playing, "关窗停")
	dlg.show_text(1, box, "%C5车芸：%C0%N这句没有配音", Color.BLACK, "")
	_ok(dlg.windows[1].voiced == "", "没有语音文件的句子不播")
	dlg.close(1)
	# mod 配音: 拿第一句的语音字节当成 mod 里一句本机没有的台词
	var fake := "%C5车芸：%C0%N这句只在 mod 里"
	var k0: String = Game.voice_key(lines[0])
	Mods.voices[Game.voice_key(fake)] = Mods.voices[k0] if Mods.voices.has(k0) else FileAccess.get_file_as_bytes(Game.voice_dir("sichuan").path_join(k0 + ".ogg"))
	dlg.show_text(1, box, fake, Color.BLACK, "")
	await process_frame
	_ok(dlg.windows[1].voiced == Game.voice_key(fake) and Game._voice.playing, "mod 里的配音能播")
	dlg.close(1)
	Mods.voices.erase(Game.voice_key(fake))
	Game.settings.set_value("audio", "voice_on", false)
	dlg.show_text(1, box, lines[0], Color.BLACK, "")
	_ok(dlg.windows[1].voiced == "", "设定关掉不播")
	dlg.close(1)
	Game.settings.set_value("audio", "voice_on", old)
	print("VOICE %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(1 if _fail else 0)
