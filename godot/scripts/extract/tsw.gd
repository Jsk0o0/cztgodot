extends RefCounted
## ACT/*.tsw (2D 界面 / 立绘 / 图标图库) → PNG + index.json (同 tools/tsw2png.py)
## TSW: 0x1c 起条目表, 每条 44 字节: name[20] (Big5), u32 大小, u32 文件偏移, u32 条目号 (0 = 空位); 表一直延续到最小的条目数据偏移
## 条目: 0x0c 起帧表, 每帧 36 字节: u32 帧数据偏移, u32 压缩大小, u32 解压大小, …, u16 宽, u16 高 (+32);
##   帧数 = (第一帧偏移 − 12) / 36; 帧数据 = LZO1X 压缩的 TEX 图像
## 输出: <out>/<tsw 名>/<条目号 4 位>_<简体名>/<帧号 3 位>.png; index.json 同 Python 版 (解码失败的帧记 error)

const Lzo := preload("res://scripts/extract/lzo.gd")
const Tex := preload("res://scripts/extract/tex.gd")
const Txt := preload("res://scripts/extract/text.gd")
const FILES := ["all_sys.tsw", "all_char.tsw", "all_item.tsw", "all_magic.tsw", "all_map1.tsw", "all_map2.tsw"]


static func read_table(d: PackedByteArray) -> Array:
	var head := d.slice(0, 0x100000)
	var recs: Array = []
	var q := 0x1C
	var data_start := -1
	while q + 44 <= head.size() and (data_start < 0 or q < data_start):
		var size := head.decode_u32(q + 20)
		var off := head.decode_u32(q + 24)
		var idx := head.decode_u32(q + 28)
		if idx:
			recs.append({"index": idx, "name": Txt.big5z(head.slice(q, q + 20)), "size": size, "offset": off})
			data_start = off if data_start < 0 else mini(data_start, off)
		q += 44
	return recs


## [[偏移, 压缩大小, 解压大小, 宽, 高], ...]; 帧表不完整返回 [] (Python 版 struct.error)
static func frames(blob: PackedByteArray) -> Array:
	if blob.size() < 16:
		return []
	var first := blob.decode_u32(12)
	var n := (first - 12) / 36
	var out: Array = []
	for k in n:
		var p := 12 + k * 36
		if p + 36 > blob.size():
			return []
		out.append([blob.decode_u32(p), blob.decode_u32(p + 4), blob.decode_u32(p + 8), blob.decode_u16(p + 32), blob.decode_u16(p + 34)])
	return out


static func decode_frame(blob: PackedByteArray, off: int, csize: int) -> Image:
	var raw := Lzo.decompress(blob.slice(off, off + csize + 8))
	return Tex.decode(raw) if raw.size() else null


## re.sub(r'[\\/:*?"<>|\s]+', '_', s).strip('_')
static func safe(s: String) -> String:
	var out := ""
	var in_run := false
	for ch in s:
		var cp := ch.unicode_at(0)
		var bad := '\\/:*?"<>|'.contains(ch) or cp in [9, 10, 11, 12, 13, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000] \
			or (cp >= 0x2000 and cp <= 0x200a)
		if bad:
			if not in_run:
				out += "_"
			in_run = true
		else:
			out += ch
			in_run = false
	return out.strip_edges(true, true).lstrip("_").rstrip("_")


## 提取全部 .tsw; progress(done, total) 每个条目回调一次
static func extract(game: String, out: String, progress := Callable()) -> Dictionary:
	var index := {}
	var jobs: Array = []
	for fn in FILES:
		var path := game.path_join("ACT").path_join(fn)
		if FileAccess.file_exists(path):
			jobs.append(fn)
	var total := jobs.size()
	var done := 0
	for fn in jobs:
		var data := FileAccess.get_file_as_bytes(game.path_join("ACT").path_join(fn))
		var stem: String = fn.get_basename()
		var items: Array = []
		for r in read_table(data):
			var blob := data.slice(r.offset, r.offset + r.size)
			# 目录表的大小可能偏小 (all_map1 第 2/26/35 条、all_sys 第 149 条), 以帧表为准
			var need := 0
			for f in frames(blob):
				need = maxi(need, int(f[0]) + int(f[1]) + 8)
			if need > blob.size():
				blob = data.slice(r.offset, r.offset + need)
			var simp := Txt.t2s(r.name)
			var rel := "%s/%04d_%s" % [stem, r.index, safe(simp)]
			var d := out.path_join(rel)
			DirAccess.make_dir_recursive_absolute(d)
			var fr: Array = []
			var lst := frames(blob)
			for k in lst.size():
				var f: Array = lst[k]
				var im := decode_frame(blob, f[0], f[1])
				if im == null:
					fr.append({"frame": k, "error": "decode failed"})
					continue
				im.save_png(d.path_join("%03d.png" % k))
				fr.append({"frame": k, "w": im.get_width(), "h": im.get_height()})
			items.append({"index": r.index, "name": r.name, "name_simplified": simp, "dir": rel, "frames": fr})
		index[stem] = items
		done += 1
		if progress.is_valid():
			progress.call(done, total)
	var f2 := FileAccess.open(out.path_join("index.json"), FileAccess.WRITE)
	f2.store_string(JSON.stringify(index, " "))
	f2.close()
	return index
