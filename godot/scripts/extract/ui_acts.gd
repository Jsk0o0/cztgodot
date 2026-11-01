extends RefCounted
## all_sys.act 里界面用的 2D ACT 动画 → ui/acts.json (同 tools/export_ui_acts.py; 播放器时序说明见该文件)
## 输出: {"9001": {"0": {"frames": [[图片相对路径, 停留逻辑帧数, 锚点x, 锚点y, 图集矩形或 null, (变换)], ...], "loop": bool}}}

const Act := preload("res://scripts/extract/act.gd")
const TSW := ["all_char", "all_item", "all_magic", "all_sys", "all_map1", "all_map2"]
const SIZE := {"PT": 1, "AT": 2, "XB": 32, "FR": 2, "AP": 2, "DE": 0, "DS": 2, "IS": 12, "PS": 2, "XF": 4,
	"CS": 12, "OC": 8, "XV": 0, "VO": 0, "2O": 0, "PC": 12, "PD": 12, "TR": 6, "VW": 2}


static func _rect(a: Array, k: int) -> Array:
	var cols := maxi((a[2] - a[0]) / a[4], 1) if a[4] else 1
	return [(k % cols) * a[4], (k / cols) * a[5], a[4], a[5]]


## 一个动作 → [帧表, 是否循环]
static func _anim(s: PackedByteArray, dirs: Dictionary) -> Array:
	var frames: Array = []
	var fr := -1
	var hold := 0
	var pc := [0.0, 0.0]
	var loop := false
	var cur: Array = []
	var atlas: Array = []
	var cell := 0
	var xf_state := {}
	var i := 0
	while i + 2 <= s.size():
		var t := Act.tag(s, i)
		if not SIZE.has(t):
			break
		var p := i + 2
		i += 2 + int(SIZE[t])
		match t:
			"FR":
				fr = s.decode_u16(p)
			"AP":
				if fr >= 0:
					var dr: Variant = dirs.get(TSW[fr / 3000], {}).get(fr % 3000)
					cur = ["ui/%s/%03d.png" % [dr, s.decode_u16(p)] if dr != null else null, 0, pc[0], pc[1], null, xf_state.duplicate()]
					if atlas.size():
						cur[4] = _rect(atlas, cell)
			"IS":
				atlas = []
				for k in 6:
					atlas.append(s.decode_u16(p + 2 * k))
				if cur.size():
					cur[4] = _rect(atlas, cell)
			"PS":
				cell = s.decode_u16(p)
				if cur.size() and atlas.size():
					cur[4] = _rect(atlas, cell)
			"CS", "OC", "PD", "XF":
				var val := {}
				if t == "CS":
					val = {"cs": [Act.rnd(s.decode_float(p), 4), Act.rnd(s.decode_float(p + 4), 4)]}
				elif t == "OC":
					val = {"oc": [s.decode_u16(p), s.decode_u16(p + 2), s.decode_u16(p + 4), s.decode_u16(p + 6)]}
				elif t == "PD":
					val = {"pd": [Act.rnd(s.decode_float(p), 2), Act.rnd(s.decode_float(p + 4), 2)]}
					xf_state.merge(val, true)
				else:
					val = {"xf": s.decode_u32(p)}
					xf_state.merge(val, true)
				if cur.size():
					(cur[5] as Dictionary).merge(val, true)
			"PC":
				pc = [s.decode_float(p), s.decode_float(p + 4)]
				if cur.size():
					cur[2] = pc[0]
					cur[3] = pc[1]
			"DS":
				var n := s.decode_u16(p)
				hold = 0 if n == 0xffff else n
			"DE":
				if cur.size() and cur[0] != null:
					cur[1] = hold + 1
					frames.append(cur)
				cur = []
			"VO", "2O":
				if cur.size() and cur[0] != null:   # 最后一帧没有 DE 时同样停 (停留值 + 1)
					cur[1] = hold + 1
					frames.append(cur)
				loop = t == "VO"
				break
	return [frames, loop]


## ui_index: tsw 提取的 index.json 内容
static func extract(game: String, ui_index: Dictionary, out_path: String) -> Dictionary:
	var dirs := {}
	for k in ui_index:
		var m := {}
		for e in ui_index[k]:
			m[int(e.index)] = e.dir
		dirs[k] = m
	var d := FileAccess.get_file_as_bytes(game.path_join("ACT").path_join(Act.ACT_FILES[3]))
	var out := {}
	var idx := Act.read_index(d)
	for slot in idx:
		var a := d.slice(idx[slot][0], idx[slot][0] + idx[slot][1])
		var cnt := a.decode_u16(0)
		var qqs := {}
		for q in cnt:
			var o := a.decode_u32(2 + 6 * q)
			var ln := a.decode_u16(2 + 6 * q + 4)
			if not ln:
				continue
			var r := _anim(a.slice(o, o + ln), dirs)
			var frames: Array = r[0]
			if frames.size():
				var fl: Array = []
				for f in frames:
					var row: Array = [f[0], f[1], Act.rnd(f[2], 2), Act.rnd(f[3], 2), f[4]]
					if not (f[5] as Dictionary).is_empty():
						row.append(f[5])
					fl.append(row)
				qqs[str(q)] = {"frames": fl, "loop": r[1]}
		if qqs.size():
			out[str(9000 + int(slot))] = qqs
	var f2 := FileAccess.open(out_path, FileAccess.WRITE)
	f2.store_string(JSON.stringify(out))
	f2.close()
	return out
