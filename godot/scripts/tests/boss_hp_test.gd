extends SceneTree
## 魔王生命上限按无符号 16 位读 (0x403b36 movzx): battle.json 里是负数的 22 个怪 → BOSSHP PASS / FAIL
## make test-boss-hp   (autoload 要等第一帧才有, 所以在 _process 里跑、用 load() 不写类型)

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var B = load("res://scripts/battle/battle.gd")
	B.load_db()
	var b = B.new()
	var fails := []
	var want := {2022: 42000, 2422: 16000, 2103: 64800, 2003: 36000, 2014: 1200}
	for id in want:
		var u = b._enemy_unit(id, 6, Vector3.ZERO, 0.0)
		var ok: bool = u.hp_max == want[id] and u.hp == want[id]
		print("BOSSHP %s %d %s hp_max=%d" % ["ok  " if ok else "FAIL", id, u.name, u.hp_max])
		if not ok:
			fails.append(id)
	print("BOSSHP PASS" if fails.is_empty() else "BOSSHP FAIL %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
	return false
