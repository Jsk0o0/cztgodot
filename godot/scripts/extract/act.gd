extends RefCounted
## ACT/*.act 动作表 (同 tools/act.py, 格式说明见该文件)
## 文件: 3000 个槽的稠密索引, 第 n 槽在偏移 12n−2 处 (u32 长度, u32 偏移, u32 ACT 号); ACT 号 = 类别 × 3000 + 槽号
## 一个 ACT = u16 动作数 + 动作数 × (u32 偏移, u16 长度); 每个动作是一串双字母指令

const PREFIX := ["CHR", "ITM", "MGC", "SYS", "MAP", "OTH"]
const ACT_FILES := ["all_char.act", "all_item.act", "all_magic.act", "all_sys.act", "all_map1.act", "all_map2.act"]
## 指令 → 操作数字节数 (同 act.py ACT_OPS)
const OPS := {"PT": 1, "AT": 2, "XB": 32, "FR": 2, "AP": 2, "OC": 8, "CS": 12, "TR": 6, "VW": 2, "XF": 4, "PL": 6, "DS": 2,
	"IS": 12, "PS": 2, "XT": 10, "XV": 0, "PD": 12, "PC": 12, "AC": 13, "DC": 13, "DE": 0, "VO": 0, "2O": 0}


static func model_file(fr: int) -> String:
	return "%s%05d" % [PREFIX[fr / 3000], fr % 3000]


## {槽号: [偏移, 长度]}, 只含非空槽
static func read_index(data: PackedByteArray) -> Dictionary:
	var out := {}
	for n in range(1, 3000):
		if 12 * n + 10 > data.size():
			break
		var size := data.decode_u32(12 * n - 2)
		var off := data.decode_u32(12 * n + 2)
		if size and off:
			out[n] = [off, size]
	return out


## bytes.find(pat, start, end)
static func find(d: PackedByteArray, pat: String, start := 0, end := -1) -> int:
	var a := pat.unicode_at(0)
	var b := pat.unicode_at(1) if pat.length() > 1 else 0
	var e := d.size() if end < 0 else mini(end, d.size())
	var i := start
	while i + 2 <= e:
		var k := d.find(a, i)
		if k < 0 or k + 2 > e:
			return -1
		if d[k + 1] == b:
			return k
		i = k + 1
	return -1


static func tag(d: PackedByteArray, i: int) -> String:
	return char(d[i]) + char(d[i + 1])


## Python round(x, n) 的近似 (float32 读出后按 n 位小数取整)
static func rnd(x: float, n: int) -> float:
	var m := pow(10.0, n)
	return roundf(x * m) / m


## 同 act.py actions(): {动作下标: {model, frames, fr, aps, sounds, marks, xform, bbox, loop}}
static func actions(data: PackedByteArray, act_id: int) -> Dictionary:
	var idx := read_index(data)
	var e: Array = idx[act_id % 3000]
	var d := data.slice(e[0], e[0] + e[1])
	var cnt := d.decode_u16(0)
	var res := {}
	for q in cnt:
		var o := d.decode_u32(2 + 6 * q)
		var ln := d.decode_u16(2 + 6 * q + 4)
		if not ln:
			continue
		var s := d.slice(o, o + ln)
		var p_fr := find(s, "FR")
		var p_at := find(s, "AT")
		if p_fr < 0:
			continue
		var fr := s.decode_u16(p_fr + 2)
		var at := s.decode_u16(p_at + 2) if p_at >= 0 else 0
		var aps: Array = []
		var sounds: Array = []
		var marks: Array = []
		var i := p_fr + 4
		var cur := {"s": [1.0, 1.0, 1.0], "o": [0.0, 0.0, 0.0], "r": [0, 0, 0], "c": [255, 255, 255, 255], "x": 0}
		var frames_x: Array = []
		while i + 2 <= s.size():
			var t := tag(s, i)
			if t == "ER":   # 变长: u16 个数 n + n × 3 个 u16 (0x41d736)
				i += 4 + 6 * s.decode_u16(i + 2)
				continue
			if OPS.has(t):
				var p := i + 2
				i += 2 + int(OPS[t])
				match t:
					"AP":
						if aps.size():
							frames_x.append(cur.duplicate())
						aps.append(s.decode_u16(p))
						cur = cur.duplicate()
						cur.s = [1.0, 1.0, 1.0]
						cur.c = [255, 255, 255, 255]
					"VW":
						sounds.append([maxi(aps.size() - 1, 0), s.decode_u16(p)])
					"CS":
						cur.s = [rnd(s.decode_float(p), 4), rnd(s.decode_float(p + 4), 4), rnd(s.decode_float(p + 8), 4)]
					"PD":
						cur.o = [rnd(s.decode_float(p), 3), rnd(s.decode_float(p + 4), 3), rnd(s.decode_float(p + 8), 3)]
					"TR":
						cur.r = [s.decode_u16(p), s.decode_u16(p + 2), s.decode_u16(p + 4)]
					"OC":   # 每个分量 2 字节, 取低字节 (0x41d500)
						cur.c = [s[p], s[p + 2], s[p + 4], s[p + 6]]
					"XF":
						cur.x = s.decode_u32(p)
			elif s[i + 1] == 0 and s[i] in [0x67, 0x65, 0x64]:   # g / e / d 记号
				marks.append([maxi(aps.size() - 1, 0), char(s[i])])
				i += 2
			else:
				i += 2
		if aps.size():
			frames_x.append(cur.duplicate())
		var xform: Array = []
		var nondef := false
		for f in frames_x:
			if f.s != [1.0, 1.0, 1.0] or f.o != [0.0, 0.0, 0.0] or f.r != [0, 0, 0] or f.c != [255, 255, 255, 255] or f.x:
				nondef = true
				break
		if nondef:
			var last: Variant = null
			for k in frames_x.size():
				var f: Dictionary = frames_x[k]
				var row: Array = f.s + f.o + f.r + f.c + [f.x]
				if row != last:
					xform.append([k] + row)
					last = row
		var p_xb := find(s, "XB", 0, p_fr)
		var bbox: Variant = null
		if p_xb >= 0:
			var b: Array = []
			for k in 8:
				b.append(rnd(s.decode_float(p_xb + 2 + 4 * k), 2))
			bbox = [b[0], b[1], b[2], b[4], b[5], b[6]]
		res[q] = {"model": model_file(fr), "frames": at, "fr": fr, "aps": aps, "sounds": sounds, "marks": marks,
			"xform": xform, "bbox": bbox, "loop": find(s, "VO") >= 0}
	return res
