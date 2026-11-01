extends RefCounted
## 标题按钮 (简体「开始 / 读取 / 设定 / 离开 / 动画 / 工坊」) → ui/custom/title_<名字>_{n,h,p}.png (同 tools/make_title_buttons.py)
## 底图取玩家的原版标题图 (0100_000_标题介面800x600/000.png 在 (480, 299 + 45 × 位置) 的 210×45 切图);
## 字形遮罩随包 (data/title_glyphs/masks.bin, tools/make_title_masks.py 生成, 不含原版像素), 这里只做合成。
## 悬停 / 按下: 两侧菱形 = 原版「開始」悬停图 006.png 和它底图的差异像素; 字先贴白色光晕再贴字色
## 混合同 PIL paste(颜色, 位置, L 遮罩): out = (底 × (255 − m) + 色 × m + 128) 再 ((t >> 8) + t) >> 8

const SRC := "ui/all_sys/0100_000_标题介面800x600"
const OUT := "ui/custom"
const INK := {"n": Color8(178, 119, 72), "h": Color8(253, 69, 2), "p": Color8(0, 0, 0)}
const X0 := {"n": [72, 105], "h": [68, 108], "p": [68, 108]}
const ORDER := ["start", "load", "workshop", "settings", "quit", "movie"]
const ITEMS := [["start", "开始"], ["load", "读取"], ["settings", "设定"], ["quit", "离开"], ["movie", "动画"], ["workshop", "工坊"]]

static var _masks := {}   # "码位_倍率" → [宽, 高, 字形, 光晕]


static func _load_masks() -> void:
	if _masks.size():
		return
	var b := FileAccess.get_file_as_bytes("res://data/title_glyphs/masks.bin")
	var p := 0
	while p + 9 <= b.size():
		var cp := b.decode_u32(p)
		var sc := b[p + 4]
		var w := b.decode_u16(p + 5)
		var h := b.decode_u16(p + 7)
		p += 9
		_masks["%d_%d" % [cp, sc]] = [w, h, b.slice(p, p + w * h), b.slice(p + w * h, p + 2 * w * h)]
		p += 2 * w * h


static func _paste(img: PackedByteArray, iw: int, ih: int, col: Color, mask: PackedByteArray, mw: int, mh: int, x0: int, y0: int) -> void:
	var c := [col.r8, col.g8, col.b8]
	for y in mh:
		var yy := y0 + y
		if yy < 0 or yy >= ih:
			continue
		for x in mw:
			var xx := x0 + x
			if xx < 0 or xx >= iw:
				continue
			var m := mask[y * mw + x]
			if m == 0:
				continue
			var o := (yy * iw + xx) * 3
			for k in 3:
				var t: int = img[o + k] * (255 - m) + int(c[k]) * m + 128
				img[o + k] = ((t >> 8) + t) >> 8


## root: extracted 或高清目录; scale: 1 (标清) / 2 (高清 ×2) / 4
static func build(root: String, scale: int) -> int:
	_load_masks()
	var bg := Image.load_from_file(root.path_join(SRC).path_join("000.png"))
	var hv := Image.load_from_file(root.path_join(SRC).path_join("006.png"))
	if bg == null or hv == null:
		return 0
	bg.convert(Image.FORMAT_RGB8)
	hv.convert(Image.FORMAT_RGB8)
	var s := bg.get_width() / 800
	var tw := 210 * s
	var th := 45 * s
	var hover0 := hv.get_data()
	var tile0 := bg.get_region(Rect2i(480 * s, 299 * s, tw, th)).get_data()
	var diamond := PackedByteArray()
	diamond.resize(tw * th)
	for r in [[42, 59], [139, 156]]:
		for y in th:
			for x in range(r[0] * s, r[1] * s):
				var o := (y * tw + x) * 3
				var d := absi(hover0[o] - tile0[o]) + absi(hover0[o + 1] - tile0[o + 1]) + absi(hover0[o + 2] - tile0[o + 2])
				if d > 40:
					diamond[y * tw + x] = 1
	DirAccess.make_dir_recursive_absolute(root.path_join(OUT))
	var n := 0
	for it in ITEMS:
		var slot := ORDER.find(it[0])
		var tile := bg.get_region(Rect2i(480 * s, (299 + 45 * slot) * s, tw, th)).get_data()
		for st in ["n", "h", "p"]:
			var img := tile.duplicate()
			if st != "n":
				for i in tw * th:
					if diamond[i]:
						img[i * 3] = hover0[i * 3]
						img[i * 3 + 1] = hover0[i * 3 + 1]
						img[i * 3 + 2] = hover0[i * 3 + 2]
			var text: String = it[1]
			for i in 2:
				var mk: Array = _masks["%d_%d" % [text.unicode_at(i), s]]
				var mw: int = mk[0]
				var mh: int = mk[1]
				var x := int(X0[st][i]) * s + floori((24 * s - mw) / 2.0)
				var y := 15 * s + floori((23 * s - mh) / 2.0)
				if st != "n":
					_paste(img, tw, th, Color.WHITE, mk[3], mw, mh, x, y)
				_paste(img, tw, th, INK[st], mk[2], mw, mh, x, y)
			Image.create_from_data(tw, th, false, Image.FORMAT_RGB8, img).save_png(root.path_join(OUT).path_join("title_%s_%s.png" % [it[0], st]))
			n += 1
	return n
